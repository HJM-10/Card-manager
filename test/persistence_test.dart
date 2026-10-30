import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app/data/local_store.dart';
import 'package:my_app/data/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('card order survives a new container without sensitive data', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore(prefs);
    final first = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
    addTearDown(first.dispose);
    await first.read(cardsProvider.notifier).bringToFront('c1');
    final second = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(LocalStore(prefs))]);
    addTearDown(second.dispose);
    expect(second.read(cardsProvider).last.id, 'c1');
    final raw = prefs.getString('cards.v1')!;
    expect(raw, isNot(contains('number')));
    expect(raw, isNot(contains('cvv')));
  });
}
