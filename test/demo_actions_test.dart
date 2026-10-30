import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app/data/providers.dart';
import 'package:my_app/features/actions/demo_action_screen.dart';

void main() {
  for (final action in ['Send', 'Request', 'TopUp']) {
    testWidgets('$action requires review and records one demo entry', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: DemoActionScreen(action: action))));
      await tester.enterText(find.byType(TextFormField).at(0), 'Test person');
      await tester.enterText(find.byType(TextFormField).at(1), '12.34');
      await tester.ensureVisible(find.text('Review demo ${action.toLowerCase()}'));
      await tester.tap(find.text('Review demo ${action.toLowerCase()}'));
      await tester.pumpAndSettle();
      expect(container.read(expensesProvider), isEmpty);
      await tester.tap(find.text('Confirm demo'));
      await tester.pumpAndSettle();
      final entry = container.read(expensesProvider).single;
      expect(entry.cents, 1234);
      expect(entry.isSpending, action == 'Send');
      expect(entry.cardId, 'c3');
    });
  }
}
