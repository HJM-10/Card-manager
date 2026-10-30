import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app/data/local_store.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/data/providers.dart';

void main() {
  test('failed writes leave cards and expenses unchanged', () async {
    final store = LocalStore(null, unavailable: true);
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final before = container.read(cardsProvider);
    await expectLater(
      container.read(cardsProvider.notifier).remove('c1'),
      throwsStateError,
    );
    expect(container.read(cardsProvider), same(before));
    await expectLater(
      container
          .read(expensesProvider.notifier)
          .upsert(
            Expense(
              id: 'e1',
              title: 'Test',
              date: DateTime.now(),
              cents: 1,
              category: 'Other',
            ),
          ),
      throwsStateError,
    );
    expect(container.read(expensesProvider), isEmpty);
    expect(store.warning.value, contains('could not be saved'));
  });
  test('duplicate cards are rejected without saving a card number', () async {
    final store = LocalStore(null);
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final cards = container.read(cardsProvider.notifier);
    await cards.addCard(number: '4242424242424242', expiry: '12/33');
    await expectLater(
      cards.addCard(number: '4242424242424242', expiry: '12/33'),
      throwsStateError,
    );
    expect(container.read(cardsProvider).length, 4);
    expect(
      store.read('cards.v1').toString(),
      isNot(contains('4242424242424242')),
    );
  });
}
