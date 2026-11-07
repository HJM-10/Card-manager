import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/data/spendtrail_api.dart';
import 'package:my_app/features/account/purchases_screen.dart';
import 'package:my_app/features/account/purchase_filters.dart';

const card = {'id': 'card-1', 'label': 'Daily', 'last4': '4242'};
Map<String, dynamic> purchase(String id) => {
  'id': id,
  'card_id': 'card-1',
  'merchant': 'Market $id',
  'amount': '1250.05',
  'occurred_at': '2026-11-05T10:30:00+05:00',
  'channel': 'pos',
  'source': 'manual',
  'kind': 'purchase',
  'status': 'approved',
};

Future<SpendTrailApi> authenticated(
  Future<http.Response> Function(http.Request) handler,
) async {
  final api = SpendTrailApi(
    client: MockClient((request) async {
      if (request.url.path == '/auth/login') {
        return http.Response(
          '{"access_token":"alice-token","user":{"name":"Alice"}}',
          200,
        );
      }
      expect(request.headers['Authorization'], 'Bearer alice-token');
      if (request.url.path == '/categories' && request.method == 'GET') {
        return http.Response(
          jsonEncode([
            {'id': 'groceries', 'name': 'Groceries'},
            {'id': 'food', 'name': 'Food'},
          ]),
          200,
        );
      }
      return handler(request);
    }),
  );
  addTearDown(api.close);
  await api.authenticate(email: 'alice@example.com', password: 'test-password');
  return api;
}

Future<void> open(
  WidgetTester tester,
  SpendTrailApi api, {
  VoidCallback? onExpired,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PurchasesScreen(api: api, onExpired: onExpired ?? () {}),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'search and combined card/category filters reach server and clear resets them',
    (tester) async {
      final queries = <Map<String, String>>[];
      final api = await authenticated((request) async {
        if (request.url.path == '/cards') {
          expect(request.url.queryParameters['include_archived'], 'true');
          return http.Response(
            jsonEncode([
              {...card, 'archived': true},
            ]),
            200,
          );
        }
        queries.add(request.url.queryParameters);
        return http.Response(jsonEncode([purchase('filtered')]), 200);
      });
      await open(tester, api);
      await tester.enterText(find.byType(TextField).first, 'Corner & Market');
      await tester.tap(find.byTooltip('Search purchases'));
      await tester.pumpAndSettle();
      expect(queries.last['search'], 'Corner & Market');
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily •••• 4242 (archived)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(queries.last, containsPair('search', 'Corner & Market'));
      expect(queries.last, containsPair('card_id', 'card-1'));
      expect(queries.last, containsPair('category_id', 'groceries'));
      expect(queries.last['offset'], '0');
      await tester.tap(find.text('Clear search & filters'));
      await tester.pumpAndSettle();
      expect(queries.last, {'limit': '25', 'offset': '0'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('existing purchase category can change, retry and clear', (
    tester,
  ) async {
    var saved = purchase('one');
    var attempts = 0;
    final api = await authenticated((request) async {
      if (request.method == 'PATCH') {
        attempts++;
        if (attempts == 1) {
          return http.Response('{"detail":"Please retry"}', 503);
        }
        final category = jsonDecode(request.body)['category_id'];
        saved = {
          ...saved,
          'category_id': category,
          'category': category == null ? null : 'Food',
        };
        return http.Response(jsonEncode(saved), 200);
      }
      return http.Response(
        jsonEncode(request.url.path == '/transactions' ? [saved] : saved),
        200,
      );
    });
    await open(tester, api);
    await tester.tap(find.text('Market one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change category'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save category'));
    await tester.pumpAndSettle();
    expect(find.text('Please retry'), findsOneWidget);
    await tester.tap(find.text('Save category'));
    await tester.pumpAndSettle();
    expect(find.text('Category: Food'), findsOneWidget);
    await tester.tap(find.text('Change category'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uncategorized').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save category'));
    await tester.pumpAndSettle();
    expect(find.text('Category: Uncategorized'), findsOneWidget);
    expect(saved['category_id'], isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom category is selected and submitted with new purchase', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    final api = await authenticated((request) async {
      if (request.url.path == '/cards') {
        return http.Response(jsonEncode([card]), 200);
      }
      if (request.url.path == '/categories' && request.method == 'POST') {
        expect(jsonDecode(request.body)['name'], 'Health');
        return http.Response('{"id":"health","name":"Health"}', 201);
      }
      if (request.method == 'POST') {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({...purchase('new'), ...submitted!}),
          201,
        );
      }
      return http.Response('[]', 200);
    });
    await open(tester, api);
    await tester.tap(find.text('Record purchase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Pharmacy');
    await tester.enterText(find.byType(TextFormField).at(1), '120.05');
    await tester.ensureVisible(find.text('New category'));
    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'Health');
    await tester.tap(find.text('Create category'));
    await tester.pumpAndSettle();
    expect(find.text('Health'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Save purchase'),
      180,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save purchase'));
    await tester.pumpAndSettle();
    expect(submitted!['category_id'], 'health');
    expect(tester.takeException(), isNull);
  });

  test(
    'date filters use local day boundaries, exact query encoding and exclusive end',
    () async {
      final filters = PurchaseFilters(
        dates: DateTimeRange(
          start: DateTime(2026, 10, 31),
          end: DateTime(2026, 11, 1),
        ),
      );
      expect(filters.before, DateTime(2026, 11, 2));
      final api = await authenticated((request) async {
        expect(request.url.queryParameters['search'], '100% & café');
        expect(request.url.queryParameters['uncategorized'], 'true');
        expect(
          request.url.queryParameters['occurred_from'],
          filters.dates!.start.toUtc().toIso8601String(),
        );
        expect(
          request.url.queryParameters['occurred_before'],
          filters.before!.toUtc().toIso8601String(),
        );
        return http.Response('[]', 200);
      });
      await api.purchases(
        search: '100% & café',
        uncategorized: true,
        occurredFrom: filters.dates!.start,
        occurredBefore: filters.before,
      );
    },
  );

  testWidgets(
    'small screen validates precision and permits correction after rejection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var attempts = 0;
      final api = await authenticated((request) async {
        if (request.url.path == '/cards') {
          return http.Response(jsonEncode([card]), 200);
        }
        if (request.method == 'POST') {
          attempts++;
          return http.Response('{"detail":"Choose another card"}', 422);
        }
        return http.Response('[]', 200);
      });
      await open(tester, api);
      await tester.tap(find.text('Record purchase'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Small screen market',
      );
      for (final value in ['0', '-1', '1.234', '1000000000000']) {
        await tester.enterText(find.byType(TextFormField).at(1), value);
        await tester.scrollUntilVisible(
          find.text('Save purchase'),
          180,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .last,
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Save purchase'),
          180,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save purchase'));
        await tester.pumpAndSettle();
        expect(attempts, 0);
      }
      await tester.enterText(find.byType(TextFormField).at(1), '10.5');
      await tester.scrollUntilVisible(
        find.text('Save purchase'),
        180,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save purchase'),
        180,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save purchase'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).at(0)).enabled,
        isTrue,
      );
      expect(find.text('Retry save'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save uses exact decimal, safe retry, refreshed history and server detail',
    (tester) async {
      final records = <Map<String, dynamic>>[];
      final bodies = <Map<String, dynamic>>[];
      final api = await authenticated((request) async {
        if (request.url.path == '/cards') {
          return http.Response(jsonEncode([card]), 200);
        }
        if (request.method == 'POST') {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (records.isEmpty) {
            records.add({...purchase('saved'), ...bodies.last});
          }
          if (bodies.length == 1) {
            throw http.ClientException('Response lost after commit');
          }
          expect(bodies.last, bodies.first);
          return http.Response(jsonEncode(records.single), 200);
        }
        if (request.url.path == '/transactions/saved') {
          return http.Response(
            jsonEncode({...records.single, 'merchant': 'Server detail'}),
            200,
          );
        }
        return http.Response(jsonEncode(records), 200);
      });
      await open(tester, api);
      expect(find.textContaining('No account purchases match'), findsOneWidget);
      await tester.tap(find.text('Record purchase'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Corner Market');
      await tester.enterText(find.byType(TextFormField).at(1), '0.00');
      await tester.scrollUntilVisible(
        find.text('Save purchase'),
        180,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save purchase'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a positive amount'), findsOneWidget);
      expect(bodies, isEmpty);
      await tester.enterText(find.byType(TextFormField).at(1), '1250.05');
      await tester.scrollUntilVisible(
        find.text('Save purchase'),
        180,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save purchase'));
      await tester.pumpAndSettle();
      expect(find.text('Retry save'), findsOneWidget);
      expect(bodies.first['amount'], '1250.05');
      expect(bodies.first['channel'], 'pos');
      expect(
        bodies.first['source_reference'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(
        DateTime.parse(bodies.first['occurred_at'] as String).isUtc,
        isTrue,
      );
      await tester.tap(find.text('Retry save'));
      await tester.pumpAndSettle();
      expect(records, hasLength(1));
      expect(find.text('Corner Market'), findsOneWidget);
      expect(find.text('PKR 1250.05'), findsOneWidget);
      await tester.tap(find.text('Corner Market'));
      await tester.pumpAndSettle();
      expect(find.text('Server detail'), findsOneWidget);
      expect(find.text('Status: approved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pagination failure retries same offset and refresh replaces history',
    (tester) async {
      var failPage = true, refreshed = false;
      final offsets = <String?>[];
      final api = await authenticated((request) async {
        offsets.add(request.url.queryParameters['offset']);
        if (request.url.queryParameters['offset'] == '25') {
          if (failPage) {
            failPage = false;
            return http.Response('{"detail":"Try later"}', 503);
          }
          return http.Response(jsonEncode([purchase('older')]), 200);
        }
        return http.Response(
          jsonEncode(
            refreshed
                ? [purchase('new')]
                : List.generate(25, (i) => purchase('$i')),
          ),
          200,
        );
      });
      await open(tester, api);
      await tester.scrollUntilVisible(
        find.text('Load more'),
        500,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Try later'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(offsets, ['0', '25', '25']);
      expect(find.text('Load more'), findsNothing);
      refreshed = true;
      await tester.tap(find.byTooltip('Refresh purchases'));
      await tester.pumpAndSettle();
      expect(find.text('Market new'), findsOneWidget);
      expect(find.text('Market 0'), findsNothing);
    },
  );

  testWidgets('empty cards and recoverable card errors fit small screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var failCards = true;
    final api = await authenticated((request) async {
      if (request.url.path == '/cards' && failCards) {
        failCards = false;
        return http.Response('{"detail":"Cards unavailable"}', 503);
      }
      return http.Response('[]', 200);
    });
    await open(tester, api);
    await tester.tap(find.text('Record purchase'));
    await tester.pumpAndSettle();
    expect(find.text('Cards unavailable'), findsOneWidget);
    await tester.tap(find.text('Reload cards'));
    await tester.pumpAndSettle();
    expect(find.text('Cards unavailable'), findsNothing);
    expect(find.text('Save purchase'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final stage in ['history', 'cards', 'save', 'detail']) {
    testWidgets('expired session during $stage returns control to sign-in', (
      tester,
    ) async {
      var expired = 0;
      final api = await authenticated((request) async {
        final shouldExpire = switch (stage) {
          'history' => request.url.path == '/transactions',
          'cards' => request.url.path == '/cards',
          'save' => request.method == 'POST',
          _ => request.url.path == '/transactions/one',
        };
        if (shouldExpire) {
          return http.Response('{"detail":"Session expired"}', 401);
        }
        if (request.url.path == '/cards') {
          return http.Response(jsonEncode([card]), 200);
        }
        return http.Response(
          jsonEncode(stage == 'detail' ? [purchase('one')] : []),
          200,
        );
      });
      await open(tester, api, onExpired: () => expired++);
      if (stage == 'cards' || stage == 'save') {
        await tester.tap(find.text('Record purchase'));
        await tester.pumpAndSettle();
      }
      if (stage == 'save') {
        await tester.enterText(find.byType(TextFormField).at(0), 'Market');
        await tester.enterText(find.byType(TextFormField).at(1), '10');
        await tester.scrollUntilVisible(
          find.text('Save purchase'),
          180,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save purchase'));
        await tester.pumpAndSettle();
      }
      if (stage == 'detail') {
        await tester.tap(find.text('Market one'));
        await tester.pumpAndSettle();
      }
      expect(expired, 1);
    });
  }
}
