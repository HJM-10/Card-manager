import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/data/spendtrail_api.dart';
import 'package:my_app/features/account/spendtrail_app.dart';

void main() {
  testWidgets('register, add masked card, sign out and sign in again', (
    tester,
  ) async {
    final records = <Map<String, dynamic>>[];
    final api = SpendTrailApi(
      client: MockClient((request) async {
        if (request.url.path.startsWith('/auth/') && request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'access_token': 'test-token',
              'user': {'name': 'Alice'},
            }),
            200,
          );
        }
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.url.path == '/cards' && request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.containsKey('cvv'), isFalse);
          expect(body['last4'], '4242');
          records.add({'id': 'card-1', ...body});
          return http.Response('{}', 201);
        }
        if (request.url.path == '/cards') {
          return http.Response(jsonEncode(records), 200);
        }
        return http.Response('', 204);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(SpendTrailApp(api: api));
    await tester.tap(find.text('New here? Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Alice');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'alice@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'synthetic-password',
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your wallet is ready'), findsOneWidget);
    await tester.tap(find.text('Add fictional card'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Daily spending');
    await tester.enterText(find.byType(TextFormField).at(1), '4242');
    await tester.enterText(find.byType(TextFormField).at(2), '12/2099');
    await tester.ensureVisible(find.text('Save card'));
    await tester.tap(find.text('Save card'));
    await tester.pumpAndSettle();
    expect(find.text('Daily spending'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'alice@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'synthetic-password',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Daily spending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server error remains visible and can be retried', (
    tester,
  ) async {
    final api = SpendTrailApi(
      client: MockClient(
        (_) async =>
            http.Response('{"detail":"Incorrect email or password"}', 401),
      ),
    );
    addTearDown(api.close);
    await tester.pumpWidget(SpendTrailApp(api: api));
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'alice@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'incorrect-password',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect email or password'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
