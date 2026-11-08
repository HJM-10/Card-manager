import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/wallet_style.dart';
import '../../data/settings.dart';
import '../../core/widgets/motion.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'card_stack.dart';
import '../expenses/expenses_screen.dart';
import '../actions/demo_action_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.accountName,
    this.appearanceAction,
    this.walletStyle,
    this.onPurchases,
  });
  final String? accountName;
  final Widget? appearanceAction;
  final WalletStyle? walletStyle;
  final VoidCallback? onPurchases;

  @override
  Widget build(BuildContext context) {
    const step = Duration(milliseconds: 90);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        physics: const BouncingScrollPhysics(),
        children: [
          FadeSlideIn(
            child: _Header(
              accountName: accountName,
              appearanceAction: appearanceAction,
              walletStyle: walletStyle,
            ),
          ),
          const SizedBox(height: 18),
          if (onPurchases != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Account purchases'),
              subtitle: const Text('Record purchases and view saved history'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onPurchases,
            ),
          FadeSlideIn(
            key: ValueKey(walletStyle),
            delay: step,
            child: CardStack(style: walletStyle),
          ),
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: Duration(milliseconds: 180),
            child: onPurchases == null
                ? _QuickActions(walletStyle: walletStyle)
                : OutlinedButton.icon(
                    onPressed: onPurchases,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Simulate purchases & refunds'),
                  ),
          ),
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: Duration(milliseconds: 270),
            child: _ExpensesSection(walletStyle: walletStyle),
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({this.accountName, this.appearanceAction, this.walletStyle});
  final String? accountName;
  final Widget? appearanceAction;
  final WalletStyle? walletStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = accountName ?? ref.watch(settingsProvider).name;
    final concept =
        walletStyle == WalletStyle.cobaltFold ||
        walletStyle == WalletStyle.figCarousel;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (concept)
                Text(
                  'SPENDTRAIL',
                  style:
                      AppText.tiny(
                        Theme.of(context).colorScheme.onSurfaceVariant,
                      ).copyWith(
                        fontFamily: walletStyle?.bodyFont,
                        letterSpacing: 1.4,
                      ),
                ),
              Text(
                concept ? 'Hello, $name' : 'Hello $name',
                style: AppText.title().copyWith(
                  fontFamily: walletStyle?.displayFont,
                ),
              ),
              if (!concept) ...[
                const SizedBox(height: 2),
                Text("Let's save your money.", style: AppText.caption()),
              ],
            ],
          ),
        ),
        if (appearanceAction != null) appearanceAction!,
        Pressable(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Notifications'),
              content: const Text(
                'You are all caught up. View your recorded activity in Expenses.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 21,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                Positioned(
                  top: 9,
                  right: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.badge,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (concept)
          CircleAvatar(
            radius: 21,
            backgroundColor: walletStyle!.tileColor(
              Theme.of(context).colorScheme,
            ),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            child: Text(
              name.trim().isEmpty
                  ? 'S'
                  : name.trim().characters.first.toUpperCase(),
            ),
          )
        else
          ClipOval(
            child: SizedBox(
              width: 42,
              height: 42,
              // Scaled up slightly to crop the square corners of the source art.
              child: Transform.scale(
                scale: 1.12,
                child: Image.asset(
                  'assets/images/avatar.jpg',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child, this.padding, this.walletStyle});
  final Widget child;
  final EdgeInsets? padding;
  final WalletStyle? walletStyle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final squared = walletStyle == WalletStyle.cobaltFold;
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(squared ? 12 : AppRadii.section),
        border: walletStyle == WalletStyle.classic
            ? Border.all(color: colors.outlineVariant.withValues(alpha: .36))
            : null,
      ),
      child: child,
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({this.walletStyle});
  final WalletStyle? walletStyle;

  static const _items = [
    (Icons.north_east_rounded, 'Send'),
    (Icons.south_west_rounded, 'Request'),
    (Icons.credit_card_rounded, 'TopUp'),
    (Icons.grid_view_rounded, 'More'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final rounded = walletStyle != WalletStyle.figCarousel;
    return _Section(
      walletStyle: walletStyle,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (icon, label) in _items)
            Pressable(
              onTap: () {
                if (label != 'More') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DemoActionScreen(action: label),
                    ),
                  );
                } else {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (sheetContext) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.receipt_long),
                            title: const Text('Expenses & activity'),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ExpensesScreen(),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.bar_chart),
                            title: const Text('Statistics'),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              ref.read(tabProvider.notifier).select(2);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.settings),
                            title: const Text('Profile & settings'),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              ref.read(tabProvider.notifier).select(3);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }
              },
              child: SizedBox(
                width: 64,
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color:
                            walletStyle?.tileColor(colors) ??
                            colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(rounded ? 999 : 11),
                      ),
                      child: Icon(
                        icon,
                        size: 19,
                        color: walletStyle == WalletStyle.classic
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: AppText.caption().copyWith(
                        fontFamily: walletStyle?.bodyFont,
                      ),
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

class _ExpensesSection extends ConsumerWidget {
  const _ExpensesSection({this.walletStyle});
  final WalletStyle? walletStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider);
    return _Section(
      walletStyle: walletStyle,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent activity',
                  style: AppText.heading().copyWith(
                    fontFamily: walletStyle?.displayFont,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ExpensesScreen(),
                  ),
                ),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (expenses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No expenses yet. Add one to start tracking.'),
            ),
          for (final e in expenses.take(5))
            InkWell(
              onTap: () => showExpenseEditor(context, expense: e),
              child: _ExpenseRow(expense: e, walletStyle: walletStyle),
            ),
          TextButton.icon(
            onPressed: () => showExpenseEditor(context),
            icon: const Icon(Icons.add),
            label: const Text('Add expense'),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends ConsumerWidget {
  const _ExpenseRow({required this.expense, this.walletStyle});
  final Expense expense;
  final WalletStyle? walletStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final banded = walletStyle == WalletStyle.figCarousel;
    final body = AppText.body().copyWith(fontFamily: walletStyle?.bodyFont);
    return Container(
      margin: banded ? const EdgeInsets.only(bottom: 5) : null,
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: banded ? 8 : 0),
      decoration: banded
          ? BoxDecoration(
              color: WalletStyle.figCarousel.tileColor(colors),
              borderRadius: BorderRadius.circular(11),
            )
          : null,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: banded ? colors.surface : colors.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(expense.icon, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.title, style: body),
                const SizedBox(height: 2),
                Text(
                  expense.timestamp,
                  style: AppText.tiny().copyWith(
                    fontFamily: walletStyle?.bodyFont,
                  ),
                ),
              ],
            ),
          ),
          Text(ref.watch(moneyProvider)(expense.amount), style: body),
        ],
      ),
    );
  }
}
