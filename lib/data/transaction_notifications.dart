import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'spendtrail_api.dart';

class TransactionAlert {
  const TransactionAlert(this.id, this.transactionId, this.userId);
  final String id, transactionId, userId;
  static TransactionAlert? parse(Map<String, dynamic> data) {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if ([
      'id',
      'transaction_id',
      'user_id',
    ].any((k) => data[k] is! String || !uuid.hasMatch(data[k] as String))) {
      return null;
    }
    return TransactionAlert(
      data['id'] as String,
      data['transaction_id'] as String,
      data['user_id'] as String,
    );
  }
}

abstract class AlertGateway {
  Stream<TransactionAlert> get opened;
  Stream<TransactionAlert> get received;
  Stream<String> get tokens;
  Future<bool> initialize();
  Future<String?> token({bool requestPermission = false});
  Future<void> disable();
  Future<void> dispose();
}

class FirebaseAlertGateway implements AlertGateway {
  final _opened = StreamController<TransactionAlert>.broadcast();
  final _received = StreamController<TransactionAlert>.broadcast();
  final _tokens = StreamController<String>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  @override
  Stream<TransactionAlert> get opened => _opened.stream;
  @override
  Stream<TransactionAlert> get received => _received.stream;
  @override
  Stream<String> get tokens => _tokens.stream;
  @override
  Future<bool> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    if ([appId, apiKey, senderId, projectId].any((v) => v.isEmpty)) {
      return false;
    }
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        appId: appId,
        apiKey: apiKey,
        messagingSenderId: senderId,
        projectId: projectId,
      ),
    );
    void forward(
      RemoteMessage message,
      StreamController<TransactionAlert> controller,
    ) {
      final alert = TransactionAlert.parse(message.data);
      if (alert != null && !controller.isClosed) controller.add(alert);
    }

    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((m) => forward(m, _opened)),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen((m) => forward(m, _received)),
    );
    _subscriptions.add(
      FirebaseMessaging.instance.onTokenRefresh.listen(
        _tokens.add,
        onError: (_) {},
      ),
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) forward(initial, _opened);
    return true;
  }

  @override
  Future<String?> token({bool requestPermission = false}) async {
    final messaging = FirebaseMessaging.instance;
    final permission = requestPermission
        ? await messaging.requestPermission()
        : await messaging.getNotificationSettings();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      return null;
    }
    await messaging.setAutoInitEnabled(true);
    final result = await messaging.getToken();
    if (result == null) {
      throw const ApiException('Alerts could not connect. Please try again.');
    }
    return result;
  }

  @override
  Future<void> disable() async {
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    await FirebaseMessaging.instance.deleteToken();
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _opened.close();
    await _received.close();
    await _tokens.close();
  }
}

String _deviceUuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class TransactionNotifications extends ChangeNotifier {
  TransactionNotifications({
    required this.api,
    required this.gateway,
    required this.onExpired,
  }) {
    _subscriptions.add(gateway.opened.listen((alert) => _queue(alert, true)));
    _subscriptions.add(
      gateway.received.listen((alert) => _queue(alert, false)),
    );
    _subscriptions.add(
      gateway.tokens.listen((_) {
        if (enabled && userId != null) unawaited(synchronize());
      }),
    );
    ready = _initialize();
  }
  final SpendTrailApi api;
  final AlertGateway gateway;
  final VoidCallback onExpired;
  final _opens = StreamController<TransactionAlert>.broadcast();
  final _banners = StreamController<TransactionAlert>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Stream<TransactionAlert> get opens => _opens.stream;
  Stream<TransactionAlert> get banners => _banners.stream;
  late final Future<void> ready;
  SharedPreferences? _preferences;
  String? userId, deviceId, error;
  bool configured = false, enabled = false, busy = false, _disposed = false;
  int _generation = 0;
  TransactionAlert? pending;
  Future<void> _events = Future.value();
  String get _scope => 'alerts.${Uri.encodeComponent(api.baseUrl)}.$userId';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  Future<void> _initialize() async {
    try {
      configured = await gateway.initialize();
      if (configured) _preferences = await SharedPreferences.getInstance();
    } catch (_) {
      error =
          'Transaction alerts could not start. Purchases can still be saved.';
    }
    _notify();
  }

  Future<void> setUser(String? id) async {
    final generation = ++_generation;
    if (id == null) pending = null;
    userId = id;
    deviceId = null;
    enabled = false;
    error = null;
    busy = false;
    _notify();
    await ready;
    if (!_current(generation) || id == null || !configured) return;
    deviceId = _preferences!.getString('$_scope.device');
    enabled = _preferences!.getBool('$_scope.enabled') ?? false;
    if (enabled) await synchronize();
    if (_current(generation) && pending != null) _queue(pending!, true);
    _notify();
  }

  Future<void> synchronize({bool requestPermission = false}) async {
    await ready;
    if (!configured || userId == null || busy || _disposed) return;
    final generation = _generation;
    final scope = _scope;
    busy = true;
    error = null;
    _notify();
    try {
      final token = await gateway.token(requestPermission: requestPermission);
      if (!_current(generation)) return;
      if (token == null) {
        if (deviceId != null) {
          try {
            await api.disableDevice(deviceId!);
          } on ApiException catch (e) {
            if (e.statusCode != 404) rethrow;
          }
        }
        if (!_current(generation)) return;
        enabled = false;
        await _preferences!.setBool('$scope.enabled', false);
        error =
            'Notifications are not allowed. You can enable them in phone settings. Purchases still save normally.';
        return;
      }
      deviceId ??= _deviceUuid();
      await _preferences!.setString('$scope.device', deviceId!);
      // Preserve the user's intent for retries if the registration response is lost.
      enabled = true;
      await _preferences!.setBool('$scope.enabled', true);
      if (!_current(generation)) return;
      await api.registerDevice(deviceId!, token);
    } on ApiException catch (e) {
      if (_current(generation)) {
        error = e.message;
        if (e.unauthorized) onExpired();
      }
    } catch (_) {
      if (_current(generation)) {
        error =
            'Alerts could not connect. Please try again. Purchases can still be saved.';
      }
    } finally {
      if (_current(generation)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> disable() async {
    if (busy || userId == null) return;
    final generation = _generation;
    busy = true;
    error = null;
    _notify();
    try {
      if (deviceId != null) {
        try {
          await api.disableDevice(deviceId!);
        } on ApiException catch (e) {
          if (e.statusCode != 404) rethrow;
        }
      }
      if (!_current(generation)) return;
      enabled = false;
      await _preferences?.setBool('$_scope.enabled', false);
      await gateway.disable();
    } on ApiException catch (e) {
      if (_current(generation)) {
        error = e.message;
        if (e.unauthorized) onExpired();
      }
    } catch (_) {
      if (_current(generation)) {
        error =
            'Alerts are disabled on your account. Phone settings may also need updating.';
      }
    } finally {
      if (_current(generation)) {
        busy = false;
        _notify();
      }
    }
  }

  void open(TransactionAlert alert) => _queue(alert, true);
  void retryOpen() {
    if (pending != null) _queue(pending!, true);
  }

  void _queue(TransactionAlert alert, bool open) {
    _events = _events.then((_) => _handle(alert, open)).catchError((Object _) {
      if (!_disposed) {
        error = 'This alert could not be opened. Please try again.';
        _notify();
      }
    });
  }

  Future<void> _handle(TransactionAlert alert, bool open) async {
    await ready;
    if (_disposed) return;
    if (userId == null) {
      if (open) pending = alert;
      return;
    }
    if (alert.userId != userId) return;
    final generation = _generation;
    final key = '$_scope.${open ? 'opened' : 'received'}';
    final seen = _preferences?.getStringList(key) ?? [];
    if (seen.contains(alert.id)) return;
    try {
      final event = await api.notification(alert.id);
      if (!_current(generation) ||
          event['transaction_id'] != alert.transactionId) {
        return;
      }
      // Access is verified by the authenticated transaction API, never payload alone.
      await api.purchase(alert.transactionId);
      if (!_current(generation)) return;
      try {
        await api.observeNotification(alert.id, open ? 'opened' : 'received');
      } on ApiException {
        /* Receipt reporting must not block opening an authorized record. */
      }
      if (!_current(generation)) return;
      seen.add(alert.id);
      await _preferences?.setStringList(
        key,
        seen.length > 200 ? seen.sublist(seen.length - 200) : seen,
      );
      if (!_current(generation)) return;
      if (open) {
        pending = null;
        _opens.add(alert);
      } else {
        _banners.add(alert);
      }
    } on ApiException catch (e) {
      if (!_current(generation)) return;
      if (open && e.statusCode != 404) pending = alert;
      error = e.statusCode == 404
          ? 'This transaction is unavailable for the signed-in account.'
          : e.message;
      if (e.unauthorized) onExpired();
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(gateway.dispose());
    unawaited(_opens.close());
    unawaited(_banners.close());
    super.dispose();
  }
}
