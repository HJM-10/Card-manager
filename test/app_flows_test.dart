import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app/main.dart';
import 'package:my_app/core/theme/app_theme.dart';
import 'package:my_app/core/theme/wallet_style.dart';
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
      UncontrolledProviderScope(
        container: container,
        child: const WalletDemoApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Hello SpendTrail user'), findsOneWidget);
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

  testWidgets('all three wallet designs fit in light and dark mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backgrounds = <Color>{};
    for (final style in WalletStyle.values) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.wallet(style, brightness);
        backgrounds.add(theme.scaffoldBackgroundColor);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: const TextScaler.linear(2),
                ),
                child: child!,
              ),
              home: AppShell(walletStyle: style),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Add Card'), findsOneWidget);
        expect(find.textContaining('Rs '), findsWidgets);
      }
    }
    expect(backgrounds, hasLength(6));
  });

  testWidgets('Cobalt Fold brings a rear card to the front', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.wallet(WalletStyle.cobaltFold, Brightness.light),
          home: const AppShell(walletStyle: WalletStyle.cobaltFold),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('•••• 9312'));
    await tester.pumpAndSettle();
    expect(container.read(cardsProvider).last.last4, '9312');
    expect(find.text('Rs 12,480.50'), findsOneWidget);
  });
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
