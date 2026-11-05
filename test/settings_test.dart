import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app/data/settings.dart';
import 'package:my_app/data/local_store.dart';

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
      expect(first.read(moneyProvider)(1234.5), 'Rs 1,234.50');
      await first
          .read(settingsProvider.notifier)
          .save(name: '  HJM  ', appearance: 'dark');
      final next = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(next.dispose);
      expect(next.read(settingsProvider).name, 'HJM');
      expect(next.read(settingsProvider).themeMode, ThemeMode.dark);
      expect(next.read(moneyProvider)(1234.5), 'Rs 1,234.50');
    },
  );
}
