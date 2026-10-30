import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/settings.dart';
import '../../core/widgets/motion.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'card_stack.dart';
import '../expenses/expenses_screen.dart';
import '../actions/demo_action_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const step = Duration(milliseconds: 90);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        physics: const BouncingScrollPhysics(),
        children: const [
          FadeSlideIn(child: _Header()),
          SizedBox(height: 18),
          FadeSlideIn(delay: step, child: CardStack()),
          SizedBox(height: 14),
          FadeSlideIn(
            delay: Duration(milliseconds: 180),
            child: _QuickActions(),
          ),
          SizedBox(height: 14),
          FadeSlideIn(
            delay: Duration(milliseconds: 270),
            child: _ExpensesSection(),
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello ${ref.watch(settingsProvider).name}',
                style: AppText.title(),
              ),
              const SizedBox(height: 2),
              Text("Let's save your money.", style: AppText.caption()),
            ],
          ),
        ),
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
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        ClipOval(
          child: SizedBox(
            width: 42,
            height: 42,
            // Scaled up slightly to crop the square corners of the source art.
            child: Transform.scale(
              scale: 1.12,
              child: Image.asset('assets/images/avatar.jpg', fit: BoxFit.cover),
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.section),
      ),
      child: child,
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  static const _items = [
    (Icons.north_east_rounded, 'Send'),
    (Icons.south_west_rounded, 'Request'),
    (Icons.credit_card_rounded, 'TopUp'),
    (Icons.grid_view_rounded, 'More'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Section(
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
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 19),
                    ),
                    const SizedBox(height: 8),
                    Text(label, style: AppText.caption()),
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
  const _ExpensesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider);
    return _Section(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Recent activity', style: AppText.heading()),
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
              child: _ExpenseRow(expense: e),
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
  const _ExpenseRow({required this.expense});
  final Expense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(expense.icon, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.title, style: AppText.body()),
                const SizedBox(height: 2),
                Text(expense.timestamp, style: AppText.tiny()),
              ],
            ),
          ),
          Text(ref.watch(moneyProvider)(expense.amount), style: AppText.body()),
        ],
      ),
    );
  }
}
