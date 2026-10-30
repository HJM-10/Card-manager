import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/card_utils.dart';
import 'local_store.dart';

const currencies = {'USD': r'$', 'PKR': 'Rs ', 'EUR': '€', 'GBP': '£'};
class AppSettings {
  const AppSettings({this.name = 'Magpie user', this.currency = 'USD', this.appearance = 'system'});
  final String name, currency, appearance;
  ThemeMode get themeMode => switch (appearance) { 'dark' => ThemeMode.dark, 'light' => ThemeMode.light, _ => ThemeMode.system };
}
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final saved = ref.read(localStoreProvider).read('settings.v1');
    if (saved is Map) {
      return AppSettings(name: saved['name'] is String ? saved['name'] as String : 'Magpie user', currency: currencies.containsKey(saved['currency']) ? saved['currency'] as String : 'USD', appearance: ['system', 'light', 'dark'].contains(saved['appearance']) ? saved['appearance'] as String : 'system');
    }
    return const AppSettings();
  }
  Future<void> save({required String name, required String currency, required String appearance}) async {
    if (name.trim().isEmpty || name.length > 50 || !currencies.containsKey(currency) || !['system', 'light', 'dark'].contains(appearance)) throw ArgumentError('Invalid settings');
    await ref.read(localStoreProvider).write('settings.v1', {'name': name.trim(), 'currency': currency, 'appearance': appearance});
    state = AppSettings(name: name.trim(), currency: currency, appearance: appearance);
  }
}
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
final moneyProvider = Provider<String Function(double)>((ref) {
  final currency = ref.watch(settingsProvider).currency;
  return (value) => formatMoney(value, symbol: currencies[currency]!);
});
