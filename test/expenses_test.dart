import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/data/providers.dart';
import 'package:my_app/data/local_store.dart';

void main() {
  test('money parser preserves cents and rejects invalid input', () {
    expect(parseAmountCents('12.30'), 1230);
    expect(parseAmountCents('0.01'), 1);
    for (final input in ['0', '-1', '1.234', 'NaN', '1e3', '']) {
      expect(parseAmountCents(input), isNull);
    }
  });
  test('expense create, edit, restore and delete', () async {
    final store = LocalStore(null);
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    Expense entry(int cents) => Expense(
      id: 'e1',
      title: 'Lunch',
      date: DateTime(2026, 10, 30),
      cents: cents,
      category: 'Food',
      cardId: 'c1',
    );
    await container.read(expensesProvider.notifier).upsert(entry(1230));
    await container.read(expensesProvider.notifier).upsert(entry(1599));
    expect(container.read(expensesProvider).single.cents, 1599);
    expect(container.read(demoBalanceProvider('c1')), 12464.51);
    final restored = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(restored.dispose);
    expect(restored.read(expensesProvider).single.cardId, 'c1');
    await restored.read(expensesProvider.notifier).remove('e1');
    expect(restored.read(expensesProvider), isEmpty);
    expect(restored.read(demoBalanceProvider('c1')), 12480.50);
  });
}
