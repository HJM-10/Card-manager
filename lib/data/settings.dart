import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/card_utils.dart';
import '../core/theme/wallet_style.dart';
import 'local_store.dart';

class AppSettings {
  const AppSettings({
    this.name = 'SpendTrail user',
    this.appearance = 'system',
    this.walletStyle = WalletStyle.classic,
  });
  final String name, appearance;
  final WalletStyle walletStyle;
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
        walletStyle:
            WalletStyle.values
                .where((style) => style.name == saved['walletStyle'])
                .firstOrNull ??
            WalletStyle.classic,
      );
    }
    return const AppSettings();
  }

  Future<void> _pending = Future<void>.value();

  Future<void> save({
    String? name,
    required String appearance,
    WalletStyle? walletStyle,
  }) {
    final pending = _pending.then(
      (_) => _save(
        name ?? state.name,
        appearance,
        walletStyle ?? state.walletStyle,
      ),
    );
    _pending = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
  }

  Future<void> _save(
    String name,
    String appearance,
    WalletStyle walletStyle,
  ) async {
    if (name.trim().isEmpty ||
        name.length > 50 ||
        !['system', 'light', 'dark'].contains(appearance)) {
      throw ArgumentError('Invalid settings');
    }
    await ref.read(localStoreProvider).write('settings.v1', {
      'name': name.trim(),
      'appearance': appearance,
      'walletStyle': walletStyle.name,
    });
    state = AppSettings(
      name: name.trim(),
      appearance: appearance,
      walletStyle: walletStyle,
    );
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
final moneyProvider = Provider<String Function(double)>(
  (ref) =>
      (value) => formatMoney(value, symbol: 'Rs '),
);
