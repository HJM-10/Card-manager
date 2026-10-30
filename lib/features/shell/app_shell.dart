import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/motion.dart';
import '../../data/providers.dart';
import '../home/home_screen.dart';
import '../cards/cards_screen.dart';
import '../statistics/statistics_screen.dart';
import '../profile/profile_screen.dart';
import '../../data/local_store.dart';

/// Hosts the tabs and the floating dark nav bar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          IndexedStack(
            index: tab,
            children: const [
              HomeScreen(),
              CardsScreen(),
              StatisticsScreen(),
              ProfileScreen(),
            ],
          ),
          // Fade content out under the nav bar.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0),
                      Theme.of(context).scaffoldBackgroundColor,
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(child: FloatingNavBar()),
          ),
          Positioned(left: 16, right: 16, top: MediaQuery.paddingOf(context).top,
            child: ValueListenableBuilder<String?>(
              valueListenable: ref.watch(localStoreProvider).warning,
              builder: (_, warning, __) => warning == null ? const SizedBox.shrink() : Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(padding: const EdgeInsets.all(12), child: Text(warning)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FloatingNavBar extends ConsumerWidget {
  const FloatingNavBar({super.key});

  static const _items = [
    (Icons.home_rounded, 'Home'),
    (Icons.receipt_long_outlined, 'Cards'),
    (Icons.insert_chart_outlined_rounded, 'Stats'),
    (Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(tabProvider);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _items.length; i++)
            Pressable(
              onTap: () => ref.read(tabProvider.notifier).select(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                height: 44,
                padding: EdgeInsets.symmetric(horizontal: i == current ? 16 : 13),
                decoration: BoxDecoration(
                  color: i == current ? AppColors.darkSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Icon(
                      _items[i].$1,
                      size: 19,
                      color: i == current ? Colors.white : Colors.white54,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      child: i == current
                          ? Padding(
                              padding: const EdgeInsets.only(left: 7),
                              child: Text(_items[i].$2,
                                  style: AppText.caption(Colors.white)),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

