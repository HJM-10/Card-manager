import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/data/local_store.dart';
import 'package:my_app/core/theme/wallet_style.dart';
import 'package:my_app/data/providers.dart';
import 'package:my_app/data/settings.dart';
import 'package:my_app/data/spendtrail_api.dart';
import 'package:my_app/features/account/spendtrail_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('spendtrail/biometric'),
          (call) async => call.method == 'status'
              ? {'available': false, 'saved': false}
              : null,
        );
  });
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
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: SpendTrailApp(api: api),
      ),
    );
    expect(find.text('SpendTrail.', findRichText: true), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Hello Alice'), findsNothing);
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
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Hello Alice'), findsOneWidget);
    expect(find.textContaining('Rs '), findsWidgets);
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == 'dark',
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
    expect(container.read(settingsProvider).walletStyle, WalletStyle.classic);
    container.read(tabProvider.notifier).select(3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SpendTrail Classic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fig Carousel').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(
      container.read(settingsProvider).walletStyle,
      WalletStyle.figCarousel,
    );
    expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
    container.read(tabProvider.notifier).select(0);
    await tester.pumpAndSettle();
    expect(find.text('Card 1 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Next card'));
    await tester.pumpAndSettle();
    expect(find.text('Card 2 of 3'), findsOneWidget);
    container.read(tabProvider.notifier).select(1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account card profiles'));
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
    expect(find.text('Hello, Alice'), findsOneWidget);
    container.read(tabProvider.notifier).select(1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account card profiles'));
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
    await tester.pumpWidget(ProviderScope(child: SpendTrailApp(api: api)));
    await tester.pumpAndSettle();
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

  testWidgets(
    'signed-in Statistics loads and refreshes account budgets then handles expiry',
    (tester) async {
      var reports = 0;
      var expire = false;
      final api = SpendTrailApi(
        client: MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return http.Response(
              '{"access_token":"test-token","user":{"id":"alice","name":"Alice"}}',
              200,
            );
          }
          if (request.url.path == '/reports/monthly') {
            reports++;
            if (expire) {
              return http.Response('{"detail":"Session expired"}', 401);
            }
            return http.Response(
              jsonEncode({
                'month': request.url.queryParameters['month'],
                'spent': '42.00',
                'purchases': '42.00',
                'refunds': '0.00',
                'transaction_count': 1,
                'categories': [],
                'cards': [],
                'budgets': [],
              }),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(api.close);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: SpendTrailApp(api: api),
        ),
      );
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
      expect(reports, 0);
      container.read(tabProvider.notifier).select(2);
      await tester.pumpAndSettle();
      expect(reports, 1);
      expect(find.text('PKR 42.00'), findsOneWidget);
      container.read(tabProvider.notifier).select(0);
      await tester.pumpAndSettle();
      container.read(tabProvider.notifier).select(2);
      await tester.pumpAndSettle();
      expect(reports, 2);
      expire = true;
      await tester.tap(find.byTooltip('Refresh account spending'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('PKR 42.00'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('appearance persists and sign-up fits a small screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    Widget app() => ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(LocalStore(preferences)),
      ],
      child: const SpendTrailApp(),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == 'dark',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account.'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isFalse,
    );
    await tester.ensureVisible(find.text('Create account'));
    expect(find.text('Create account').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
