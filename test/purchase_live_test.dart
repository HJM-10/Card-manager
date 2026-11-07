import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/data/spendtrail_api.dart';

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
    },
    skip: liveUrl.isEmpty ? 'Set LIVE_API_URL to a dedicated test API.' : false,
  );
}
