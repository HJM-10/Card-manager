import 'package:flutter_test/flutter_test.dart';
import 'package:spendtrail/data/spendtrail_api.dart';

// Opt in against a dedicated test API: creates synthetic accounts and records.
const liveUrl = String.fromEnvironment('LIVE_API_URL');

void main() {
  test(
    'real HTTP purchase persists across clients and is isolated by account',
    () async {
      final email =
          'purchase-${DateTime.now().microsecondsSinceEpoch}@example.com';
      const password = 'synthetic-test-password';
      final api = SpendTrailApi(baseUrl: liveUrl);
      final restarted = SpendTrailApi(baseUrl: liveUrl);
      final other = SpendTrailApi(baseUrl: liveUrl);
      addTearDown(api.close);
      addTearDown(restarted.close);
      addTearDown(other.close);
      await api.authenticate(
        email: email,
        password: password,
        name: 'Purchase Check',
      );
      await api.saveCard({
        'label': 'Test card',
        'network': 'visa',
        'last4': '4242',
        'expiry_month': 12,
        'expiry_year': 2099,
      });
      final card = (await api.cards()).single;
      final categories = await api.categories();
      final groceries = categories.firstWhere((c) => c['name'] == 'Groceries');
      final food = categories.firstWhere((c) => c['name'] == 'Food');
      final body = {
        'card_id': card['id'],
        'merchant': 'Live Market',
        'amount': '1250.05',
        'occurred_at': '2026-11-05T10:30:00+05:00',
        'channel': 'online',
        'source_reference': '46e3bc1e-38f9-43d5-a9e7-6d5a61cdb30b',
        'category_id': groceries['id'],
      };
      final saved = await api.recordPurchase(body);
      expect((await api.recordPurchase(body))['id'], saved['id']);
      await api.logout();
      await restarted.authenticate(email: email, password: password);
      expect((await restarted.purchases()).single, saved);
      expect(await restarted.purchase(saved['id'] as String), saved);
      expect(saved['amount'], '1250.05');
      expect(saved['category'], 'Groceries');
      final recategorized = await restarted.categorizePurchase(
        saved['id'] as String,
        food['id'] as String,
      );
      expect(recategorized['category'], 'Food');
      expect((await restarted.recordPurchase(body))['category'], 'Food');
      expect(
        await restarted.purchases(
          search: 'live market',
          cardId: card['id'] as String,
          categoryId: food['id'] as String,
          occurredFrom: DateTime.parse('2026-11-05T00:00:00+05:00'),
          occurredBefore: DateTime.parse('2026-11-06T00:00:00+05:00'),
        ),
        [recategorized],
      );
      expect(
        await restarted.purchases(categoryId: groceries['id'] as String),
        isEmpty,
      );
      final health = await restarted.createCategory('Health');
      expect(health['name'], 'Health');
      await expectLater(
        restarted.createCategory('health'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
      expect(await restarted.purchases(limit: 1, offset: 1), isEmpty);
      await other.authenticate(
        email: 'other-$email',
        password: password,
        name: 'Other',
      );
      expect(await other.purchases(), isEmpty);
      await expectLater(
        other.categorizePurchase(saved['id'] as String, null),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await expectLater(
        other.purchase(saved['id'] as String),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await restarted.archiveCard(card['id'] as String);
      expect((await restarted.purchases()).single['id'], saved['id']);
      final biometricCredential = await restarted.enableBiometric();
      await restarted.lock();
      final resumed = SpendTrailApi(baseUrl: liveUrl);
      addTearDown(resumed.close);
      expect(
        (await resumed.biometricLogin(biometricCredential))['email'],
        email,
      );
      expect((await resumed.purchases()).single['id'], saved['id']);
      await resumed.disableBiometric();
      await expectLater(
        restarted.biometricLogin(biometricCredential),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      await resumed.logout();
      final importer = SpendTrailApi(baseUrl: liveUrl);
      addTearDown(importer.close);
      await importer.authenticate(email: email, password: password);
      await importer.saveCard({
        'label': 'CSV card',
        'network': 'visa',
        'last4': '9876',
        'expiry_month': 12,
        'expiry_year': 2099,
      });
      final importCard = (await importer.cards()).single;
      const csv =
          'reference,merchant,amount,occurred_at,channel,category\n'
          'live-csv-1,Bookshop,1599.00,2026-11-07T14:30:00+05:00,pos,Shopping\n'
          'live-csv-2,Café,550.00,2026-11-07T09:00:00+05:00,pos,Food\n';
      final preview = await importer.previewCsv(
        cardId: importCard['id'] as String,
        fileName: 'live.csv',
        text: csv,
      );
      expect(preview['ready_count'], 2);
      expect((await importer.purchases()).length, 1);
      final receipt = await importer.confirmCsv(
        preview['id'] as String,
        preview['preview_token'] as String,
      );
      expect(receipt['imported_count'], 2);
      expect(receipt['total_amount'], '2149.00');
      expect(
        await importer.confirmCsv(
          preview['id'] as String,
          preview['preview_token'] as String,
        ),
        receipt,
      );
      expect(
        await importer.previewCsv(
          cardId: importCard['id'] as String,
          fileName: 'renamed.csv',
          text: csv,
        ),
        receipt,
      );
      expect((await importer.purchases()).length, 3);
      final simulation = {
        ...body,
        'card_id': importCard['id'],
        'status': 'declined',
      };
      final declined = await importer.simulatePurchase(simulation);
      expect(
        (await importer.simulatePurchase(simulation))['id'],
        declined['id'],
      );
      expect(
        (await importer.purchases(status: 'declined')).single['id'],
        declined['id'],
      );
      final refundBody = {
        'amount': '250.05',
        'occurred_at': '2026-11-08T12:00:00+05:00',
        'source_reference': '91e3bc1e-38f9-43d5-a9e7-6d5a61cdb30b',
      };
      final refund = await importer.refundPurchase(
        saved['id'] as String,
        refundBody,
      );
      expect(refund['original_purchase_id'], saved['id']);
      expect(
        (await importer.refundPurchase(
          saved['id'] as String,
          refundBody,
        ))['id'],
        refund['id'],
      );
      expect(
        (await importer.purchases(kind: 'refund')).single['id'],
        refund['id'],
      );
      await expectLater(
        other.refundPurchase(saved['id'] as String, refundBody),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await expectLater(
        other.csvImport(preview['id'] as String),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await importer.saveBudget('2026-11', food['id'] as String, '2000.00');
      await importer.saveBudget('2026-11', food['id'] as String, '2000.00');
      final monthly = await importer.monthlyReport('2026-11');
      expect(monthly['spent'], '3149.00');
      final budget =
          (monthly['budgets'] as List).single as Map<String, dynamic>;
      expect(budget['spent'], '1550.00');
      expect(budget['remaining'], '450.00');
      expect(budget['percent'], '77.50');
      expect(
        (await importer.monthlyReport(
          '2026-11',
          cardId: card['id'] as String,
        ))['spent'],
        '1000.00',
      );
      await expectLater(
        other.saveBudget('2026-11', food['id'] as String, '100.00'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await importer.saveBudget('2026-11', food['id'] as String, '1500.00');
      final budgetRestart = SpendTrailApi(baseUrl: liveUrl);
      addTearDown(budgetRestart.close);
      await budgetRestart.authenticate(email: email, password: password);
      final restored =
          (await budgetRestart.monthlyReport('2026-11'))['budgets'] as List;
      expect(restored.single['remaining'], '-50.00');
      expect(restored.single['over_budget'], isTrue);
      await budgetRestart.removeBudget('2026-11', food['id'] as String);
      expect(
        (await budgetRestart.monthlyReport('2026-11'))['budgets'],
        isEmpty,
      );
      const alertDevice = 'f9751543-b4cb-427c-9336-8a0d32193005';
      const alertToken = 'synthetic-token-for-real-http-client-check';
      await budgetRestart.registerDevice(alertDevice, alertToken);
      await budgetRestart.registerDevice(alertDevice, '$alertToken-rotated');
      expect(await budgetRestart.notifications(), isEmpty);
      await expectLater(
        other.registerDevice(alertDevice, alertToken),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await budgetRestart.disableDevice(alertDevice);
    },
    skip: liveUrl.isEmpty ? 'Set LIVE_API_URL to a dedicated test API.' : false,
  );
}
