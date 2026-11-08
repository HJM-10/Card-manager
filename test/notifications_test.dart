import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spendtrail/data/spendtrail_api.dart';
import 'package:spendtrail/data/transaction_notifications.dart';
import 'package:spendtrail/features/account/notification_settings.dart';
import 'package:spendtrail/features/account/spendtrail_app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'biometric_test.dart' as biometric;

const alice = 'f9751543-b4cb-427c-9336-8a0d32193001';
const bob = 'f9751543-b4cb-427c-9336-8a0d32193002';
const eventId = 'f9751543-b4cb-427c-9336-8a0d32193003';
const transactionId = 'f9751543-b4cb-427c-9336-8a0d32193004';
const alert = TransactionAlert(eventId, transactionId, alice);

class FakeGateway implements AlertGateway {
  final openStream = StreamController<TransactionAlert>.broadcast();
  final receiveStream = StreamController<TransactionAlert>.broadcast();
  final tokenStream = StreamController<String>.broadcast();
  bool supported = true, permissionRequested = false, disabled = false;
  String? currentToken = 'synthetic-token-for-this-test-device';
  TransactionAlert? initial;
  @override
  Stream<TransactionAlert> get opened => openStream.stream;
  @override
  Stream<TransactionAlert> get received => receiveStream.stream;
  @override
  Stream<String> get tokens => tokenStream.stream;
  @override
  Future<bool> initialize() async {
    if (initial != null) openStream.add(initial!);
    return supported;
  }

  @override
  Future<String?> token({bool requestPermission = false}) async {
    permissionRequested |= requestPermission;
    return currentToken;
  }

  @override
  Future<void> disable() async {
    disabled = true;
  }

  @override
  Future<void> dispose() async {
    await openStream.close();
    await receiveStream.close();
    await tokenStream.close();
  }
}

Future<void> drain() async {
  for (var i = 0; i < 25; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

SpendTrailApi apiFor(
  List<http.Request> requests, {
  int notificationStatus = 200,
}) {
  final api = SpendTrailApi(
    client: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/notifications/$eventId') {
        return http.Response(
          jsonEncode({'id': eventId, 'transaction_id': transactionId}),
          notificationStatus,
        );
      }
      if (request.url.path == '/transactions/$transactionId') {
        return http.Response(jsonEncode({'id': transactionId}), 200);
      }
      if (request.url.path.endsWith('/observations')) {
        return http.Response('', 204);
      }
      return http.Response('{}', 200);
    }),
  );
  addTearDown(api.close);
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'permission denial does not register a device or block saving',
    () async {
      final requests = <http.Request>[];
      final api = apiFor(requests);
      final gateway = FakeGateway()..currentToken = null;
      final service = TransactionNotifications(
        api: api,
        gateway: gateway,
        onExpired: () {},
      );
      addTearDown(service.dispose);
      await service.setUser(alice);
      await service.synchronize(requestPermission: true);
      expect(gateway.permissionRequested, isTrue);
      expect(service.enabled, isFalse);
      expect(service.error, contains('not allowed'));
      expect(requests, isEmpty);
      await api.recordPurchase({'synthetic': 'purchase'});
      expect(requests.single.url.path, '/transactions');
    },
  );

  test(
    'device token rotation reuses account device and disable revokes it',
    () async {
      final requests = <http.Request>[];
      final gateway = FakeGateway();
      final service = TransactionNotifications(
        api: apiFor(requests),
        gateway: gateway,
        onExpired: () {},
      );
      addTearDown(service.dispose);
      await service.setUser(alice);
      await service.synchronize(requestPermission: true);
      final path = requests.single.url.path;
      gateway.currentToken = 'synthetic-rotated-token-for-device';
      gateway.tokenStream.add(gateway.currentToken!);
      await drain();
      expect(requests.length, 2);
      expect(requests.last.url.path, path);
      expect(jsonDecode(requests.last.body)['token'], gateway.currentToken);
      await service.disable();
      expect(requests.last.method, 'DELETE');
      expect(service.enabled, isFalse);
      expect(gateway.disabled, isTrue);
    },
  );

  test(
    'tap verifies event and transaction ownership and suppresses repeats after restart',
    () async {
      final requests = <http.Request>[];
      final api = apiFor(requests);
      final gateway = FakeGateway();
      final service = TransactionNotifications(
        api: api,
        gateway: gateway,
        onExpired: () {},
      );
      await service.setUser(alice);
      final opened = service.opens.first;
      gateway.openStream.add(alert);
      expect(
        (await opened.timeout(const Duration(seconds: 2))).transactionId,
        transactionId,
      );
      expect(requests.map((r) => r.url.path), [
        '/notifications/$eventId',
        '/transactions/$transactionId',
        '/notifications/$eventId/observations',
      ]);
      gateway.openStream.add(alert);
      await drain();
      expect(requests.length, 3);
      service.dispose();
      final restartedGateway = FakeGateway();
      final restarted = TransactionNotifications(
        api: api,
        gateway: restartedGateway,
        onExpired: () {},
      );
      addTearDown(restarted.dispose);
      await restarted.setUser(alice);
      restartedGateway.openStream.add(alert);
      await drain();
      expect(requests.length, 3);
    },
  );

  test(
    'cold notification waits for matching sign-in and foreground duplicates show one banner',
    () async {
      final requests = <http.Request>[];
      final gateway = FakeGateway()..initial = alert;
      final service = TransactionNotifications(
        api: apiFor(requests),
        gateway: gateway,
        onExpired: () {},
      );
      addTearDown(service.dispose);
      await service.ready;
      await drain();
      expect(requests, isEmpty);
      final opened = service.opens.first;
      await service.setUser(alice);
      await opened.timeout(const Duration(seconds: 2));
      final banners = <TransactionAlert>[];
      final subscription = service.banners.listen(banners.add);
      addTearDown(subscription.cancel);
      gateway.receiveStream.add(alert);
      gateway.receiveStream.add(alert);
      await drain();
      expect(banners.length, 1);
      expect(jsonDecode(requests.last.body)['action'], 'received');
    },
  );

  test(
    'wrong account and inaccessible transaction never navigate; expiry is handled',
    () async {
      final requests = <http.Request>[];
      final gateway = FakeGateway();
      var expired = false;
      final service = TransactionNotifications(
        api: apiFor(requests, notificationStatus: 401),
        gateway: gateway,
        onExpired: () => expired = true,
      );
      addTearDown(service.dispose);
      var opens = 0;
      final subscription = service.opens.listen((_) => opens++);
      addTearDown(subscription.cancel);
      await service.setUser(bob);
      gateway.openStream.add(alert);
      await drain();
      expect(requests, isEmpty);
      await service.setUser(alice);
      gateway.openStream.add(alert);
      await drain();
      expect(opens, 0);
      expect(expired, isTrue);
      expect(requests.length, 1);
      expect(
        TransactionAlert.parse({
          'id': '../../transactions',
          'transaction_id': transactionId,
          'user_id': alice,
        }),
        isNull,
      );
    },
  );

  testWidgets(
    'unconfigured settings clearly disable alerts while leaving history available',
    (tester) async {
      final gateway = FakeGateway()..supported = false;
      final service = TransactionNotifications(
        api: apiFor([]),
        gateway: gateway,
        onExpired: () {},
      );
      addTearDown(service.dispose);
      await service.ready;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationSettings(alerts: service, onHistory: () {}),
          ),
        ),
      );
      expect(find.textContaining('not connected yet'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(find.text('Alert history'), findsOneWidget);
    },
  );

  testWidgets(
    'cold alert opens the authorized transaction after password sign-in',
    (tester) async {
      final gateway = FakeGateway()..initial = alert;
      final api = SpendTrailApi(
        client: MockClient((request) async {
          if (request.url.path == '/auth/login') {
            return http.Response(
              jsonEncode({
                'access_token': 'test',
                'user': {'id': alice, 'name': 'Alice'},
              }),
              200,
            );
          }
          if (request.url.path == '/notifications/$eventId') {
            return http.Response(
              jsonEncode({'transaction_id': transactionId}),
              200,
            );
          }
          if (request.url.path.endsWith('/observations')) {
            return http.Response('', 204);
          }
          return http.Response(
            jsonEncode({
              'id': transactionId,
              'merchant': 'Alert Market',
              'amount': '12.35',
              'occurred_at': '2026-11-08T12:00:00+05:00',
              'kind': 'purchase',
              'status': 'approved',
              'source': 'manual',
              'channel': 'pos',
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          child: SpendTrailApp(
            api: api,
            biometricVault: biometric.FakeVault(),
            alertGateway: gateway,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Purchase details'), findsNothing);
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
      expect(find.text('Purchase details'), findsOneWidget);
      expect(find.text('Alert Market'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
