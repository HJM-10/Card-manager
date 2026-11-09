import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendtrail/core/theme/app_theme.dart';
import 'package:spendtrail/core/widgets/motion.dart';
import 'package:spendtrail/data/providers.dart';
import 'package:spendtrail/data/settings.dart';
import 'package:spendtrail/data/spendtrail_api.dart';
import 'package:spendtrail/features/account/spendtrail_app.dart';
import 'package:spendtrail/features/account/purchases_screen.dart';
import 'package:spendtrail/features/account/monthly_budget_screen.dart';
import 'package:spendtrail/features/shell/app_shell.dart';
import 'package:spendtrail/features/splash/splash_screen.dart';

import 'biometric_test.dart' as biometric;
import 'purchases_test.dart' as purchases;
import 'monthly_budget_test.dart' as budgets;

Future<void> guidelines(WidgetTester tester) async {
  final semantics = tester.ensureSemantics();
  try {
    await tester.pump();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    expect(tester.takeException(), isNull);
  } finally {
    semantics.dispose();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    final appearance = dark ? 'dark' : 'light';
    testWidgets('login accessibility: $appearance', (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SpendTrailApi(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(api.close);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(settingsProvider.notifier)
          .save(appearance: appearance);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: SpendTrailApp(api: api, biometricVault: biometric.FakeVault()),
        ),
      );
      await tester.pumpAndSettle();
      await guidelines(tester);
      await tester.tap(find.text('New here? Create account'));
      await tester.pumpAndSettle();
      await guidelines(tester);
    });

    testWidgets('purchase and budget accessibility: $appearance', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = await purchases.authenticated((request) async {
        final Object result;
        if (request.url.path == '/cards') {
          result = [purchases.card];
        } else if (request.url.path == '/reports/monthly') {
          result = budgets.report(amount: '1500.00');
        } else {
          result = [purchases.purchase('one')];
        }
        return http.Response(jsonEncode(result), 200);
      });
      final theme = dark ? AppTheme.dark() : AppTheme.light();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: PurchasesScreen(api: api, onExpired: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await guidelines(tester);
      await tester.tap(find.text('Record purchase'));
      await tester.pumpAndSettle();
      await guidelines(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: MonthlyBudgetScreen(
              api: api,
              onExpired: () {},
              initialMonth: DateTime(2026, 11),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await guidelines(tester);
    });
  }

  testWidgets('navigation and alerts are labeled 48dp targets', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AppShell(onPurchases: () {}, onNotifications: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['Home', 'Cards', 'Stats', 'Profile']) {
      final node = tester.getSemantics(find.bySemanticsLabel(label).last);
      expect(node.rect.height, greaterThanOrEqualTo(48));
      expect(node.rect.width, greaterThanOrEqualTo(48));
    }
    expect(find.byTooltip('Transaction alerts'), findsOneWidget);
    expect(
      tester.getSize(find.byTooltip('Transaction alerts')).shortestSide,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.bySemanticsLabel('Profile').last);
    await tester.pumpAndSettle();
    expect(container.read(tabProvider), 3);
    semantics.dispose();
  });

  testWidgets(
    'reduced motion completes splash without its 2.9 second animation',
    (tester) async {
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: SplashScreen(onComplete: () => completed = true),
        ),
      );
      await tester.pump();
      expect(completed, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('custom actions activate with keyboard Enter and Space', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Pressable(
            onTap: () => activations++,
            child: const Text('Keyboard action'),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(activations, 2);
  });

  for (final scenario in [
    (const Size(320, 568), 2.0),
    (const Size(844, 390), 1.0),
  ]) {
    testWidgets(
      'account forms fit ${scenario.$1} at ${scenario.$2} text scale',
      (tester) async {
        tester.view.physicalSize = scenario.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = await purchases.authenticated(
          (request) async => http.Response(
            jsonEncode(
              request.url.path == '/cards'
                  ? [purchases.card]
                  : [purchases.purchase('one')],
            ),
            200,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scenario.$2)),
              child: child!,
            ),
            home: PurchasesScreen(api: api, onExpired: () {}),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Record purchase'));
        await tester.tap(find.text('Record purchase'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Save purchase'),
          150,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .last,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
