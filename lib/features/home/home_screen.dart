import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/card_utils.dart';
import '../../core/widgets/motion.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'card_stack.dart';
import '../expenses/expenses_screen.dart';

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

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hello DailyFlutterUI', style: AppText.title()),
              const SizedBox(height: 2),
              Text("Let's save your money.", style: AppText.caption()),
            ],
          ),
        ),
        Pressable(
          onTap: () {},
          child: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_none_rounded,
                    size: 21, color: AppColors.textPrimary),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.section),
      ),
      child: child,
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  static const _items = [
    (Icons.north_east_rounded, 'Send'),
    (Icons.south_west_rounded, 'Request'),
    (Icons.credit_card_rounded, 'TopUp'),
    (Icons.grid_view_rounded, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Section(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (icon, label) in _items)
            Pressable(
              onTap: () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text('$label is coming soon'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 1),
                )),
              child: SizedBox(
                width: 64,
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: AppColors.iconTile,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 19, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(label, style: AppText.caption(AppColors.textPrimary)),
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
              Text('Manage Expenses', style: AppText.heading()),
              const Spacer(),
              TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ExpensesScreen())), child: const Text('View All')),
            ],
          ),
          const SizedBox(height: 6),
          if (expenses.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No expenses yet. Add one to start tracking.')),
          for (final e in expenses.take(5)) InkWell(onTap: () => showExpenseEditor(context, expense: e), child: _ExpenseRow(expense: e)),
          TextButton.icon(onPressed: () => showExpenseEditor(context), icon: const Icon(Icons.add), label: const Text('Add expense')),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense});
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.iconTile,
              shape: BoxShape.circle,
            ),
            child: Icon(expense.icon, size: 19, color: AppColors.textPrimary),
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
          Text(formatMoney(expense.amount), style: AppText.body()),
        ],
      ),
    );
  }
}
