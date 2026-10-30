import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app/main.dart';
import 'package:my_app/core/theme/app_theme.dart';
import 'package:my_app/data/providers.dart';
import 'package:my_app/data/settings.dart';
import 'package:my_app/features/shell/app_shell.dart';
import 'package:my_app/features/add_card/add_card_sheet.dart';

void main() {
  testWidgets('splash reaches home, then add card completes', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MagpieApp()),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Hello Magpie user'), findsOneWidget);
    await tester.tap(find.text('Add Card'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '4242424242424242');
    await tester.enterText(find.byType(TextField).at(1), '1233');
    await tester.enterText(find.byType(TextField).at(2), '123');
    await tester.pump();
    await tester.tap(
      find
          .descendant(
            of: find.byType(AddCardSheet),
            matching: find.text('Add Card'),
          )
          .last,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Adding your card...'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(container.read(cardsProvider).last.last4, '4242');
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('all tabs fit a small screen at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(settingsProvider.notifier)
          .save(
            name: 'A long profile name for layout checks',
            currency: 'PKR',
            appearance: 'dark',
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const AppShell(),
          ),
        ),
      );
      for (var tab = 0; tab < 4; tab++) {
        container.read(tabProvider.notifier).select(tab);
        await tester.pumpAndSettle();
      }
    });
  }
  testWidgets('add-card form scrolls above keyboard on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(tabProvider.notifier).select(1);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const AppShell()),
      ),
    );
    await tester.tap(find.text('Add Card'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '123');
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a valid 16-digit Visa or Mastercard.'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find
          .descendant(
            of: find.byType(AddCardSheet),
            matching: find.text('Add Card'),
          )
          .last,
    );
    expect(tester.takeException(), isNull);
  });
}
