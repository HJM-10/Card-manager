import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/data/spendtrail_api.dart';
import 'package:my_app/features/account/csv_import_screen.dart';

import 'purchases_test.dart' as fixtures;

Map<String, dynamic> batch({bool invalid = false, bool confirmed = false}) => {
  'id': 'batch-1',
  'preview_token': 'preview-1',
  'file_name': 'purchases.csv',
  'status': confirmed ? 'confirmed' : 'preview',
  'ready_count': invalid ? 0 : 1,
  'duplicate_count': 1,
  'error_count': invalid ? 1 : 0,
  'imported_count': confirmed ? 1 : 0,
  'total_amount': '1599.00',
  'can_confirm': !invalid && !confirmed,
  'rows': [
    {
      'row': 2,
      'merchant': 'Bookshop',
      'amount': invalid ? '0' : '1599.00',
      'category': 'Shopping',
      'state': invalid
          ? 'error'
          : confirmed
          ? 'imported'
          : 'ready',
      'message': invalid ? 'Amount must be positive' : 'Ready to import',
    },
    {
      'row': 3,
      'merchant': 'Coffee',
      'amount': '550.00',
      'category': 'Food',
      'state': 'duplicate',
      'message': 'Matching reference; will be skipped',
    },
  ],
};

Future<void> openImport(
  WidgetTester tester,
  SpendTrailApi api, {
  String text =
      'reference,merchant,amount,occurred_at,channel\nr1,Bookshop,1599.00,2026-11-07T10:00:00+05:00,pos\n',
  XFile? file,
  bool cancel = false,
  VoidCallback? onExpired,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CsvImportScreen(
        api: api,
        onExpired: onExpired ?? () {},
        chooseFile: () async => cancel
            ? null
            : file ??
                  XFile.fromData(
                    Uint8List.fromList(utf8.encode(text)),
                    path: 'purchases.csv',
                    name: 'purchases.csv',
                  ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> scrollTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    180,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'upload previews without saving, then retries same confirmation after response loss',
    (tester) async {
      var confirms = 0, previews = 0;
      final api = await fixtures.authenticated((request) async {
        if (request.url.path == '/cards') {
          return http.Response(jsonEncode([fixtures.card]), 200);
        }
        if (request.url.path == '/imports/preview') {
          previews++;
          final body = jsonDecode(request.body);
          expect(body['card_id'], 'card-1');
          expect(body['csv_text'], contains('Bookshop'));
          return http.Response(jsonEncode(batch()), 200);
        }
        expect(request.url.path, '/imports/batch-1/confirm');
        expect(jsonDecode(request.body), {'preview_token': 'preview-1'});
        confirms++;
        if (confirms == 1) {
          throw http.ClientException('Response lost after commit');
        }
        return http.Response(jsonEncode(batch(confirmed: true)), 200);
      });
      await openImport(tester, api);
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      expect(previews, 1);
      expect(confirms, 0);
      await scrollTo(tester, 'Confirm import');
      await tester.tap(find.text('Confirm import'));
      await tester.pumpAndSettle();
      expect(find.text('Retry confirmation'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find
                  .ancestor(
                    of: find.text('Choose CSV file'),
                    matching: find.byWidgetPredicate((w) => w is FilledButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      await scrollTo(tester, 'Retry confirmation');
      await tester.tap(find.text('Retry confirmation'));
      await tester.pumpAndSettle();
      expect(confirms, 2);
      expect(find.text('Import complete'), findsOneWidget);
      expect(find.text('1 added · 1 duplicates skipped'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'row errors block confirmation and display actionable feedback on a small screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = await fixtures.authenticated((request) async {
        if (request.url.path == '/cards') {
          return http.Response(jsonEncode([fixtures.card]), 200);
        }
        expect(request.url.path, '/imports/preview');
        return http.Response(jsonEncode(batch(invalid: true)), 200);
      });
      await openImport(tester, api);
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'Confirm import');
      expect(
        tester
            .widget<FilledButton>(
              find
                  .ancestor(
                    of: find.text('Confirm import'),
                    matching: find.byWidgetPredicate((w) => w is FilledButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      await scrollTo(tester, 'Amount must be positive');
      expect(find.text('Amount must be positive'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid encoding and oversized files never reach preview API', (
    tester,
  ) async {
    var requests = 0;
    final api = await fixtures.authenticated((request) async {
      expect(request.url.path, '/cards');
      requests++;
      return http.Response(jsonEncode([fixtures.card]), 200);
    });
    await openImport(
      tester,
      api,
      file: XFile.fromData(
        Uint8List.fromList([255, 254]),
        path: 'bad.csv',
        name: 'bad.csv',
      ),
    );
    await tester.tap(find.text('Choose CSV file'));
    await tester.pumpAndSettle();
    expect(
      find.text('Save the file as UTF-8 CSV and try again.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await openImport(
      tester,
      api,
      file: XFile.fromData(
        Uint8List(maxCsvBytes + 1),
        path: 'large.csv',
        name: 'large.csv',
      ),
    );
    await tester.tap(find.text('Choose CSV file'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose a CSV file no larger than 256 KiB.'),
      findsOneWidget,
    );
    expect(requests, 2);
  });

  testWidgets(
    'picker cancellation makes no preview request and sample is previewed explicitly',
    (tester) async {
      var previews = 0;
      final api = await fixtures.authenticated((request) async {
        if (request.url.path == '/cards') {
          return http.Response(jsonEncode([fixtures.card]), 200);
        }
        expect(request.url.path, '/imports/preview');
        expect(jsonDecode(request.body)['file_name'], 'spendtrail-sample.csv');
        previews++;
        return http.Response(jsonEncode(batch()), 200);
      });
      await openImport(tester, api, cancel: true);
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      expect(previews, 0);
      await tester.tap(find.text('Try sample CSV'));
      await tester.pumpAndSettle();
      expect(previews, 1);
    },
  );

  testWidgets(
    'stale confirmation requires a new preview and session expiry returns to sign-in',
    (tester) async {
      var expired = 0, previews = 0;
      final api = await fixtures.authenticated((request) async {
        if (request.url.path == '/cards') {
          return http.Response(jsonEncode([fixtures.card]), 200);
        }
        if (request.url.path == '/imports/preview') {
          previews++;
          if (previews > 1) {
            return http.Response('{"detail":"Session expired"}', 401);
          }
          return http.Response(jsonEncode(batch()), 200);
        }
        return http.Response(
          '{"detail":"This preview has changed. Preview the file again."}',
          409,
        );
      });
      await openImport(tester, api, onExpired: () => expired++);
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'Confirm import');
      await tester.tap(find.text('Confirm import'));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'Preview again');
      await tester.tap(find.text('Preview again'));
      await tester.pumpAndSettle();
      expect(expired, 1);
    },
  );
}
