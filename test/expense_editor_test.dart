import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app/data/providers.dart';
import 'package:my_app/features/expenses/expenses_screen.dart';

void main() {
  testWidgets('expense editor saves, edits and deletes a record', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ExpensesScreen()),
      ),
    );
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Lunch');
    await tester.enterText(find.byType(TextFormField).at(1), '15.99');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(container.read(expensesProvider).single.cents, 1599);
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '20.50');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(container.read(expensesProvider).single.cents, 2050);
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete activity'));
    await tester.tap(find.text('Delete activity'));
    await tester.pumpAndSettle();
    expect(container.read(expensesProvider), isEmpty);
  });
}
