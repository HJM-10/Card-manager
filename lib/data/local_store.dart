import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only non-sensitive demo data belongs here. Never write card numbers or CVV.
class LocalStore {
  LocalStore(this.preferences);
  final SharedPreferences? preferences;
  final warning = ValueNotifier<String?>(null);
  final Map<String, Object> _memory = {};

  Object? read(String key) {
    final raw = preferences?.getString(key);
    if (raw == null) return _memory[key];
    try {
      return jsonDecode(raw);
    } catch (_) {
      warning.value = 'Saved data could not be read. Default data is shown.';
      return null;
    }
  }

  Future<void> write(String key, Object value) async {
    try {
      final success = await preferences?.setString(key, jsonEncode(value));
      if (success == false) throw StateError('Storage unavailable');
      _memory[key] = value;
      warning.value = null;
    } catch (_) {
      warning.value = 'Changes could not be saved. Please try again.';
      rethrow;
    }
  }
}

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore(null));
