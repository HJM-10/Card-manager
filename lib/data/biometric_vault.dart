import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BiometricStatus {
  const BiometricStatus({
    this.supported = false,
    this.available = false,
    this.saved = false,
  });
  final bool supported, available, saved;
}

class BiometricException implements Exception {
  const BiometricException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => message;
}

abstract class BiometricVault {
  Future<BiometricStatus> status();
  Future<void> save(String token, String server);
  Future<String> unlock(String server);
  Future<void> clear();
}

/// The Android channel encrypts and decrypts through a biometric-bound
/// Keystore CryptoObject. Flutter preferences never contain credentials.
class AndroidBiometricVault implements BiometricVault {
  static const channel = MethodChannel('spendtrail/biometric');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<T?> invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw BiometricException(
        e.message ?? 'Fingerprint login is unavailable. Use your password.',
        cancelled: e.code == 'cancelled',
      );
    }
  }

  @override
  Future<BiometricStatus> status() async {
    if (!supported) return const BiometricStatus();
    try {
      final result = await invoke<Map>('status');
      return BiometricStatus(
        supported: true,
        available: result?['available'] == true,
        saved: result?['saved'] == true,
      );
    } on MissingPluginException {
      return const BiometricStatus();
    }
  }

  @override
  Future<void> save(String token, String server) async {
    if (!supported) {
      throw const BiometricException(
        'Fingerprint login is supported on Android phones.',
      );
    }
    await invoke<void>('save', {'token': token, 'server': server});
  }

  @override
  Future<String> unlock(String server) async {
    final token = await invoke<String>('unlock', {'server': server});
    if (token == null || token.isEmpty) {
      throw const BiometricException('Use your password to sign in.');
    }
    return token;
  }

  @override
  Future<void> clear() async {
    if (!supported) return;
    try {
      await invoke<void>('clear');
    } on MissingPluginException {
      /* No saved credential on unsupported targets. */
    }
  }
}
