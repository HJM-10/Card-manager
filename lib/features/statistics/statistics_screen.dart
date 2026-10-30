import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers.dart';
import '../../data/statistics.dart';
import '../../core/utils/card_utils.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});
  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}
class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  Widget build(BuildContext context) {
    final summary = SpendingSummary(ref.watch(expensesProvider), month);
    final largest = summary.monthly.values.fold(1, max);
    final categories = summary.categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 140), children: [
      Text('Statistics', style: Theme.of(context).textTheme.headlineMedium),
      const Text('Recorded spending only. Demo requests and top-ups are excluded.'),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(tooltip: 'Previous month', icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
        Text('${month.month}/${month.year}', style: Theme.of(context).textTheme.titleLarge),
        IconButton(tooltip: 'Next month', icon: const Icon(Icons.chevron_right), onPressed: month.year == DateTime.now().year && month.month == DateTime.now().month ? null : () => setState(() => month = DateTime(month.year, month.month + 1))),
      ]),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Total spent'), Text(formatMoney(summary.totalCents / 100), style: Theme.of(context).textTheme.headlineLarge), Text('${summary.count} spending entries'),
      ]))),
      const SizedBox(height: 16),
      Text('By category', style: Theme.of(context).textTheme.titleLarge),
      if (categories.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('No spending this month. Add an expense to see a breakdown.')),
      for (final entry in categories) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: [
        Row(children: [Expanded(child: Text(entry.key)), Text(formatMoney(entry.value / 100))]),
        const SizedBox(height: 6),
        Semantics(label: '${entry.key}: ${(entry.value / summary.totalCents * 100).round()} percent', child: LinearProgressIndicator(value: entry.value / summary.totalCents, minHeight: 8, borderRadius: BorderRadius.circular(4))),
      ])),
      const SizedBox(height: 20),
      Text('Six-month trend', style: Theme.of(context).textTheme.titleLarge),
      for (final entry in summary.monthly.entries) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(children: [
        Row(children: [Expanded(child: Text('${entry.key.month}/${entry.key.year}')), Text(formatMoney(entry.value / 100))]),
        const SizedBox(height: 6), LinearProgressIndicator(value: entry.value / largest, minHeight: 12, borderRadius: BorderRadius.circular(6)),
      ])),
    ]));
  }
}
