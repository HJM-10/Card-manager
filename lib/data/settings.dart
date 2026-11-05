import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/card_utils.dart';
import 'local_store.dart';

class AppSettings {
  const AppSettings({
    this.name = 'SpendTrail user',
    this.appearance = 'system',
  });
  final String name, appearance;
  ThemeMode get themeMode => switch (appearance) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final saved = ref.read(localStoreProvider).read('settings.v1');
    if (saved is Map) {
      return AppSettings(
        name: saved['name'] is String && saved['name'] != 'Magpie user'
            ? saved['name'] as String
            : 'SpendTrail user',
        appearance: ['system', 'light', 'dark'].contains(saved['appearance'])
            ? saved['appearance'] as String
            : 'system',
      );
    }
    return const AppSettings();
  }

  Future<void> save({required String name, required String appearance}) async {
    if (name.trim().isEmpty ||
        name.length > 50 ||
        !['system', 'light', 'dark'].contains(appearance)) {
      throw ArgumentError('Invalid settings');
    }
    await ref.read(localStoreProvider).write('settings.v1', {
      'name': name.trim(),
      'appearance': appearance,
    });
    state = AppSettings(name: name.trim(), appearance: appearance);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
final moneyProvider = Provider<String Function(double)>(
  (ref) =>
      (value) => formatMoney(value, symbol: 'Rs '),
);
