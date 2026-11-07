import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_app/data/biometric_vault.dart';
import 'package:my_app/data/providers.dart';
import 'package:my_app/data/spendtrail_api.dart';
import 'package:my_app/features/account/spendtrail_app.dart';

class FakeVault implements BiometricVault {
  bool available = true, saved = false;
  String? token;
  BiometricException? saveError, unlockError;
  int unlocks = 0;
  @override
  Future<BiometricStatus> status() async =>
      BiometricStatus(supported: true, available: available, saved: saved);
  @override
  Future<void> save(String token, String server) async {
    if (saveError != null) throw saveError!;
    this.token = token;
    saved = true;
  }

  @override
  Future<String> unlock(String server) async {
    unlocks++;
    if (unlockError != null) throw unlockError!;
    return token!;
  }

  @override
  Future<void> clear() async {
    token = null;
    saved = false;
  }
}

const refreshToken = 'synthetic-refresh-credential-32-characters';

void main() {
  testWidgets('lock hides the account even when the backend is offline', (
    tester,
  ) async {
    final vault = FakeVault();
    final api = SpendTrailApi(
      client: MockClient((request) async {
        if (request.url.path == '/auth/login') {
          return http.Response(
            '{"access_token":"access","user":{"name":"Alice"}}',
            200,
          );
        }
        if (request.url.path == '/auth/access') {
          throw http.ClientException('Offline');
        }
        return http.Response(jsonEncode({'refresh_token': refreshToken}), 201);
      }),
    );
    addTearDown(api.close);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: SpendTrailApp(api: api, biometricVault: vault),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'alice@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    container.read(tabProvider.notifier).select(3);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fingerprint login'));
    await tester.tap(find.text('Fingerprint login'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lock app'));
    await tester.tap(find.text('Lock app'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with fingerprint'), findsOneWidget);
    expect(find.text('Hello Alice'), findsNothing);
    expect(vault.saved, isTrue);
  });

  testWidgets('enable, lock, fingerprint login and explicit sign-out', (
    tester,
  ) async {
    final vault = FakeVault();
    var refreshes = 0, revocations = 0;
    final api = SpendTrailApi(
      client: MockClient((request) async {
        if (request.url.path == '/auth/login') {
          return http.Response(
            '{"access_token":"password-access","user":{"name":"Alice"}}',
            200,
          );
        }
        if (request.url.path == '/auth/biometric' && request.method == 'POST') {
          expect(request.headers['Authorization'], 'Bearer password-access');
          return http.Response(
            jsonEncode({'refresh_token': refreshToken}),
            201,
          );
        }
        if (request.url.path == '/auth/biometric/refresh') {
          refreshes++;
          expect(jsonDecode(request.body), {'refresh_token': refreshToken});
          return http.Response(
            '{"access_token":"fingerprint-access","user":{"name":"Alice"}}',
            200,
          );
        }
        if (request.url.path == '/auth/session') {
          revocations++;
          expect(request.headers['Authorization'], 'Bearer fingerprint-access');
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
        child: SpendTrailApp(api: api, biometricVault: vault),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'alice@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    container.read(tabProvider.notifier).select(3);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fingerprint login'));
    await tester.tap(find.text('Fingerprint login'));
    await tester.pumpAndSettle();
    expect(vault.saved, isTrue);
    await tester.ensureVisible(find.text('Lock app'));
    await tester.tap(find.text('Lock app'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with fingerprint'), findsOneWidget);
    await tester.ensureVisible(find.text('Sign in with fingerprint'));
    await tester.tap(find.text('Sign in with fingerprint'));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(vault.unlocks, 1);
    expect(find.text('Hello Alice'), findsOneWidget);
    container.read(tabProvider.notifier).select(3);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      180,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(revocations, 1);
    expect(vault.saved, isFalse);
    expect(find.text('Sign in with fingerprint'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in ['cancel', 'expired', 'offline', 'unavailable']) {
    testWidgets('$scenario fingerprint login keeps password fallback', (
      tester,
    ) async {
      final vault = FakeVault()
        ..saved = true
        ..token = refreshToken;
      if (scenario == 'cancel') {
        vault.unlockError = const BiometricException(
          'Fingerprint check cancelled.',
          cancelled: true,
        );
      }
      if (scenario == 'unavailable') vault.available = false;
      var requests = 0;
      final api = SpendTrailApi(
        client: MockClient((request) async {
          requests++;
          if (scenario == 'offline') throw http.ClientException('Offline');
          return http.Response(
            '{"detail":"Fingerprint login has expired. Please sign in with your password."}',
            401,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          child: SpendTrailApp(api: api, biometricVault: vault),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign in with fingerprint'));
      if (scenario == 'unavailable') {
        expect(
          tester
              .widget<OutlinedButton>(
                find
                    .ancestor(
                      of: find.text('Sign in with fingerprint'),
                      matching: find.byWidgetPredicate(
                        (w) => w is OutlinedButton,
                      ),
                    )
                    .first,
              )
              .onPressed,
          isNull,
        );
      } else {
        await tester.tap(find.text('Sign in with fingerprint'));
        await tester.pumpAndSettle();
      }
      expect(
        requests,
        scenario == 'cancel' || scenario == 'unavailable' ? 0 : 1,
      );
      expect(vault.saved, scenario != 'expired');
      expect(find.text('Sign in'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'cancelled enrollment revokes server credential and leaves switch off',
    (tester) async {
      final vault = FakeVault()
        ..saveError = const BiometricException(
          'Fingerprint check cancelled.',
          cancelled: true,
        );
      var disabled = false;
      final api = SpendTrailApi(
        client: MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return http.Response(
              '{"access_token":"access","user":{"name":"Alice"}}',
              200,
            );
          }
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({'refresh_token': refreshToken}),
              201,
            );
          }
          if (request.url.path == '/auth/biometric' &&
              request.method == 'DELETE') {
            disabled = true;
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
          child: SpendTrailApp(api: api, biometricVault: vault),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'alice@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      container.read(tabProvider.notifier).select(3);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fingerprint login'));
      await tester.tap(find.text('Fingerprint login'));
      await tester.pumpAndSettle();
      expect(disabled, isTrue);
      expect(vault.saved, isFalse);
      expect(find.text('Fingerprint check cancelled.'), findsOneWidget);
    },
  );

  test(
    'Android vault forwards server binding and preserves cancellation errors',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AndroidBiometricVault.channel, (
        call,
      ) async {
        if (call.method == 'status') return {'available': true, 'saved': true};
        expect(call.arguments['server'], 'https://example.com');
        if (call.method == 'save') {
          expect(call.arguments['token'], refreshToken);
          return null;
        }
        throw PlatformException(code: 'cancelled', message: 'Cancelled');
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AndroidBiometricVault.channel,
          null,
        ),
      );
      final vault = AndroidBiometricVault();
      expect((await vault.status()).saved, isTrue);
      await vault.save(refreshToken, 'https://example.com');
      await expectLater(
        vault.unlock('https://example.com'),
        throwsA(
          isA<BiometricException>().having(
            (e) => e.cancelled,
            'cancelled',
            isTrue,
          ),
        ),
      );
    },
  );
}
