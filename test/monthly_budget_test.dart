import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spendtrail/data/spendtrail_api.dart';
import 'package:spendtrail/features/account/monthly_budget_screen.dart';

import 'purchases_test.dart' as fixtures;

Map<String, dynamic> report({
  String month = '2026-11',
  String? amount,
  String? cardId,
}) => {
  'month': month,
  'timezone': 'Asia/Karachi',
  'currency': 'PKR',
  'card_id': cardId,
  'spent': '1300.00',
  'purchases': '1550.05',
  'refunds': '250.05',
  'transaction_count': 4,
  'categories': [
    {
      'id': 'groceries',
      'name': 'Groceries',
      'spent': '1300.00',
      'transaction_count': 4,
    },
  ],
  'cards': [
    {...fixtures.card, 'archived': true},
  ],
  'budgets': [
    if (amount != null)
      {
        'category_id': 'groceries',
        'category': 'Groceries',
        'amount': amount,
        'spent': '1300.00',
        'remaining': amount == '1500.00' ? '200.00' : '-300.00',
        'percent': amount == '1500.00' ? '86.67' : '130.00',
        'over_budget': amount != '1500.00',
      },
  ],
  'budget_scope': 'all_cards',
};

Future<void> open(
  WidgetTester tester,
  SpendTrailApi api, {
  VoidCallback? onExpired,
  bool active = true,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: MonthlyBudgetScreen(
          api: api,
          onExpired: onExpired ?? () {},
          active: active,
          initialMonth: DateTime(2026, 11),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('budget create edit remove and exact limit validation', (
    tester,
  ) async {
    String? amount;
    final saved = <String>[];
    final api = await fixtures.authenticated((request) async {
      if (request.method == 'PUT') {
        expect(request.url.path, '/budgets/2026-11/groceries');
        amount = jsonDecode(request.body)['amount'] as String;
        saved.add(amount!);
        return http.Response('{}', 200);
      }
      if (request.method == 'DELETE') {
        amount = null;
        return http.Response('', 204);
      }
      return http.Response(jsonEncode(report(amount: amount)), 200);
    });
    await open(tester, api);
    await tester.ensureVisible(find.text('Set category budget'));
    await tester.tap(find.text('Set category budget'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monthly limit (PKR)'),
      '0',
    );
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(
      find.text('Enter a positive limit with up to two decimal places.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monthly limit (PKR)'),
      '1500',
    );
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();
    expect(saved, ['1500.00']);
    await tester.ensureVisible(find.text('Remaining PKR 200.00'));
    expect(find.text('86.67% used'), findsOneWidget);
    await tester.ensureVisible(find.text('Edit budget'));
    await tester.tap(find.text('Edit budget'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monthly limit (PKR)'),
      '1000.00',
    );
    await tester.tap(find.text('Save budget'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Over budget by PKR 300.00'));
    expect(find.text('130.00% used'), findsOneWidget);
    await tester.ensureVisible(find.text('Edit budget'));
    await tester.tap(find.text('Edit budget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove budget'));
    await tester.pumpAndSettle();
    expect(amount, isNull);
    expect(
      find.text(
        'No budgets for this month. Set a category limit to track your progress.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'report card and month selection use server data and clear stale results on error',
    (tester) async {
      final queries = <Map<String, String>>[];
      final api = await fixtures.authenticated((request) async {
        queries.add(request.url.queryParameters);
        if (request.url.queryParameters['month'] == '2026-12') {
          return http.Response('{"detail":"Report unavailable"}', 503);
        }
        return http.Response(
          jsonEncode(
            report(
              amount: '1500.00',
              cardId: request.url.queryParameters['card_id'],
            ),
          ),
          200,
        );
      });
      await open(tester, api);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily •••• 4242 (archived)').last);
      await tester.pumpAndSettle();
      expect(queries.last['card_id'], 'card-1');
      expect(find.text('Edit budget'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Next month'));
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(queries.last, {'month': '2026-12', 'card_id': 'card-1'});
      expect(find.text('Report unavailable'), findsOneWidget);
      expect(find.text('PKR 1300.00'), findsNothing);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('PKR 1300.00'), findsWidgets);
    },
  );

  testWidgets(
    'budget retry after uncertain save keeps the same month category and amount',
    (tester) async {
      final attempts = <String>[];
      final api = await fixtures.authenticated((request) async {
        if (request.method == 'PUT') {
          attempts.add('${request.url.path}:${request.body}');
          if (attempts.length == 1) throw http.ClientException('Lost response');
          return http.Response('{}', 200);
        }
        return http.Response(jsonEncode(report()), 200);
      });
      await open(tester, api);
      await tester.ensureVisible(find.text('Set category budget'));
      await tester.tap(find.text('Set category budget'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Monthly limit (PKR)'),
        '12.35',
      );
      await tester.tap(find.text('Save budget'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Cannot reach SpendTrail. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Save budget'));
      await tester.pumpAndSettle();
      expect(attempts.length, 2);
      expect(attempts.first, attempts.last);
    },
  );

  testWidgets(
    'report expiry invokes sign-in handling and inactive tab does not fetch',
    (tester) async {
      var calls = 0;
      var expired = false;
      final api = await fixtures.authenticated((request) async {
        calls++;
        return http.Response('{"detail":"Sign in"}', 401);
      });
      await open(tester, api, active: false, onExpired: () => expired = true);
      expect(calls, 0);
      await open(tester, api, onExpired: () => expired = true);
      expect(calls, 1);
      expect(expired, isTrue);
    },
  );

  testWidgets('monthly budget form fits small screens with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = await fixtures.authenticated(
      (request) async =>
          http.Response(jsonEncode(report(amount: '1500.00')), 200),
    );
    await open(tester, api, scale: 2);
    await tester.scrollUntilVisible(find.text('Edit budget'), 250);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit budget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit budget'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save budget'));
    expect(tester.takeException(), isNull);
  });
}
