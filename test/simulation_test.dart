import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'purchases_test.dart' as fixtures;

void main() {
  testWidgets(
    'declined simulation retains identical request after a lost response',
    (tester) async {
      final attempts = <String>[];
      final api = await fixtures.authenticated((request) async {
        if (request.url.path == '/cards') {
          return http.Response(jsonEncode([fixtures.card]), 200);
        }
        if (request.url.path == '/simulations/purchases') {
          attempts.add(request.body);
          if (attempts.length == 1) throw http.ClientException('Lost response');
          return http.Response(
            jsonEncode({
              ...fixtures.purchase('declined'),
              'status': 'declined',
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      });
      await fixtures.open(tester, api);
      await tester.tap(find.text('Simulate purchase'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Merchant'),
        'Test shop',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (PKR)'),
        '12.35',
      );
      final outcome = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Approved',
      );
      await tester.ensureVisible(outcome);
      await tester.tap(outcome);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Declined').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save purchase'));
      await tester.tap(find.text('Save purchase'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Retry save'));
      await tester.tap(find.text('Retry save'));
      await tester.pumpAndSettle();
      expect(attempts.length, 2);
      expect(attempts.first, attempts.last);
      expect(jsonDecode(attempts.first)['status'], 'declined');
      expect(find.text('Account purchases'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('approved purchase opens refund and submits only refund fields', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    final original = fixtures.purchase('original');
    final api = await fixtures.authenticated((request) async {
      if (request.url.path.endsWith('/refunds')) {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            ...original,
            'kind': 'refund',
            'original_purchase_id': 'original',
          }),
          201,
        );
      }
      return http.Response(
        jsonEncode(request.url.path == '/transactions' ? [original] : original),
        200,
      );
    });
    await fixtures.open(tester, api);
    await tester.tap(find.text('Market original'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simulate refund'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (PKR)'),
      '250.05',
    );
    await tester.ensureVisible(find.text('Save refund'));
    await tester.tap(find.text('Save refund'));
    await tester.pumpAndSettle();
    expect(submitted!.keys.toSet(), {
      'amount',
      'occurred_at',
      'source_reference',
    });
    expect(submitted!['amount'], '250.05');
    expect(find.text('Purchase details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('declined purchases have no refund action', (tester) async {
    final declined = {...fixtures.purchase('declined'), 'status': 'declined'};
    final api = await fixtures.authenticated(
      (request) async => http.Response(
        jsonEncode(request.url.path == '/transactions' ? [declined] : declined),
        200,
      ),
    );
    await fixtures.open(tester, api);
    await tester.tap(find.text('Market declined'));
    await tester.pumpAndSettle();
    expect(find.text('Simulate refund'), findsNothing);
    expect(find.text('Status: declined'), findsOneWidget);
  });
}
