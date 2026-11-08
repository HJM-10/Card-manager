import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendtrail/data/settings.dart';
import 'package:spendtrail/data/local_store.dart';
import 'package:spendtrail/core/theme/wallet_style.dart';

void main() {
  test(
    'older currency settings still display PKR and preserve appearance',
    () async {
      final store = LocalStore(null);
      await store.write('settings.v1', {
        'name': 'Magpie user',
        'currency': 'USD',
      });
      final first = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(first.dispose);
      expect(first.read(settingsProvider).name, 'SpendTrail user');
      expect(first.read(settingsProvider).walletStyle, WalletStyle.classic);
      expect(first.read(moneyProvider)(1234.5), 'Rs 1,234.50');
      await first
          .read(settingsProvider.notifier)
          .save(
            name: '  HJM  ',
            appearance: 'dark',
            walletStyle: WalletStyle.figCarousel,
          );
      await first.read(settingsProvider.notifier).save(appearance: 'light');
      final next = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(next.dispose);
      expect(next.read(settingsProvider).name, 'HJM');
      expect(next.read(settingsProvider).themeMode, ThemeMode.light);
      expect(next.read(settingsProvider).walletStyle, WalletStyle.figCarousel);
      expect(next.read(moneyProvider)(1234.5), 'Rs 1,234.50');
    },
  );
}
