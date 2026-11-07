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
      final body = {
        'card_id': card['id'],
        'merchant': 'Live Market',
        'amount': '1250.05',
        'occurred_at': '2026-11-05T10:30:00+05:00',
        'channel': 'online',
        'source_reference': '46e3bc1e-38f9-43d5-a9e7-6d5a61cdb30b',
      };
      final saved = await api.recordPurchase(body);
      expect((await api.recordPurchase(body))['id'], saved['id']);
      await api.logout();
      await restarted.authenticate(email: email, password: password);
      expect((await restarted.purchases()).single, saved);
      expect(await restarted.purchase(saved['id'] as String), saved);
      expect(saved['amount'], '1250.05');
      expect(await restarted.purchases(limit: 1, offset: 1), isEmpty);
      await other.authenticate(
        email: 'other-$email',
        password: password,
        name: 'Other',
      );
      expect(await other.purchases(), isEmpty);
      await expectLater(
        other.purchase(saved['id'] as String),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await restarted.archiveCard(card['id'] as String);
      expect((await restarted.purchases()).single['id'], saved['id']);
    },
    skip: liveUrl.isEmpty ? 'Set LIVE_API_URL to a dedicated test API.' : false,
  );
}
