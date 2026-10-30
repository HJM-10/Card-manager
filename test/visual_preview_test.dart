import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_app/core/theme/app_theme.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/data/providers.dart';
import 'package:my_app/features/shell/app_shell.dart';

/// Regenerates local review images; these are outputs, not golden baselines.
void main() {
  testWidgets('render light and dark previews with recorded spending', (
    tester,
  ) async {
    final font = FontLoader('PlusJakartaSans')
      ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(expensesProvider.notifier)
        .upsert(
          Expense(
            id: 'preview',
            title: 'Groceries',
            date: DateTime.now(),
            cents: 4250,
            category: 'Food',
            cardId: 'c1',
          ),
        );
    final boundary = GlobalKey();
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: RepaintBoundary(key: boundary, child: const AppShell()),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/avatar.jpg'),
          boundary.currentContext!,
        ),
      );
      for (final tab in [0, 1, 2, 3]) {
        container.read(tabProvider.notifier).select(tab);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/qa/${dark ? 'dark' : 'light'}-$tab.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    debugDisableShadows = true;
  });
}
