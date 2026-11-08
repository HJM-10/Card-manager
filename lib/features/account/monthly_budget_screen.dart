import 'package:flutter/material.dart';

import '../../data/spendtrail_api.dart';

String _month(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

class MonthlyBudgetScreen extends StatefulWidget {
  const MonthlyBudgetScreen({
    super.key,
    required this.api,
    required this.onExpired,
    this.active = true,
    this.initialMonth,
  });
  final SpendTrailApi api;
  final VoidCallback onExpired;
  final bool active;
  final DateTime? initialMonth;
  @override
  State<MonthlyBudgetScreen> createState() => _MonthlyBudgetScreenState();
}

class _MonthlyBudgetScreenState extends State<MonthlyBudgetScreen> {
  late DateTime month;
  String? cardId, error;
  Map<String, dynamic>? report;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    final now =
        widget.initialMonth ??
        DateTime.now().toUtc().add(const Duration(hours: 5));
    month = DateTime(now.year, now.month);
    if (widget.active) load();
  }

  @override
  void didUpdateWidget(covariant MonthlyBudgetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
      report = null;
    });
    try {
      final result = await widget.api.monthlyReport(
        _month(month),
        cardId: cardId,
      );
      if (mounted) setState(() => report = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        widget.onExpired();
        return;
      }
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void changeMonth(int change) {
    setState(() => month = DateTime(month.year, month.month + change));
    load();
  }

  Future<void> editBudget([Map<String, dynamic>? budget]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BudgetEditor(
        api: widget.api,
        month: _month(month),
        onExpired: widget.onExpired,
        categories: (report!['categories'] as List)
            .cast<Map<String, dynamic>>(),
        budgets: (report!['budgets'] as List).cast<Map<String, dynamic>>(),
        initial: budget,
      ),
    );
    if (saved == true && mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final budgets = (report?['budgets'] as List?) ?? [];
    final categories = (report?['categories'] as List?) ?? [];
    final cards = (report?['cards'] as List?) ?? [];
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
          children: [
            Text(
              'Statistics',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Text('Monthly budgets & account spending'),
            const SizedBox(height: 8),
            const Text(
              'Months follow Pakistan time. Approved purchases less refunds; declines excluded from spending.',
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: loading || month.year == 2000 && month.month == 1
                      ? null
                      : () => changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    _month(month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: loading || month.year == 2100 && month.month == 12
                      ? null
                      : () => changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: 'Refresh account spending',
                  onPressed: loading ? null : load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (loading) const Center(child: CircularProgressIndicator()),
            if (error != null) ...[
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(onPressed: load, child: const Text('Retry')),
            ],
            if (report != null) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('report-card-$cardId'),
                initialValue: cardId ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Spending by card',
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All cards')),
                  for (final card in cards)
                    DropdownMenuItem(
                      value: card['id'] as String,
                      child: Text(
                        '${card['label']} •••• ${card['last4']}${card['archived'] == true ? ' (archived)' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: loading
                    ? null
                    : (v) {
                        setState(() => cardId = v == '' ? null : v);
                        load();
                      },
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Net spending'),
                      Text(
                        'PKR ${report!['spent']}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text('Purchases: PKR ${report!['purchases']}'),
                      Text('Refunds: PKR ${report!['refunds']}'),
                      Text(
                        '${report!['transaction_count']} records, including declines',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Monthly category budgets',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text('Budgets cover all cards for this month.'),
              if (cardId != null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Choose All cards to view and edit your monthly budgets.',
                  ),
                )
              else ...[
                FilledButton.icon(
                  onPressed: () => editBudget(),
                  icon: const Icon(Icons.add),
                  label: const Text('Set category budget'),
                ),
                if (budgets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No budgets for this month. Set a category limit to track your progress.',
                    ),
                  ),
                for (final budget in budgets)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            budget['category'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Spent PKR ${budget['spent']} of PKR ${budget['amount']}',
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            label:
                                '${budget['category']}: ${budget['percent']} percent of budget used',
                            child: LinearProgressIndicator(
                              value:
                                  (double.parse(budget['percent'] as String) /
                                          100)
                                      .clamp(0.0, 1.0),
                              color: budget['over_budget'] == true
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('${budget['percent']}% used'),
                          Text(
                            budget['over_budget'] == true
                                ? 'Over budget by PKR ${(budget['remaining'] as String).replaceFirst('-', '')}'
                                : 'Remaining PKR ${budget['remaining']}',
                          ),
                          TextButton(
                            onPressed: () =>
                                editBudget(budget as Map<String, dynamic>),
                            child: const Text('Edit budget'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Text(
                'Spending by category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (report!['transaction_count'] == 0)
                const Text('No account activity for this month.'),
              for (final category in categories)
                if (category['transaction_count'] != 0)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(category['name'] as String),
                    subtitle: Text('PKR ${category['spent']}'),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetEditor extends StatefulWidget {
  const _BudgetEditor({
    required this.api,
    required this.month,
    required this.categories,
    required this.budgets,
    required this.onExpired,
    this.initial,
  });
  final SpendTrailApi api;
  final String month;
  final List<Map<String, dynamic>> categories, budgets;
  final Map<String, dynamic>? initial;
  final VoidCallback onExpired;
  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.initial?['amount'] as String? ?? '',
  );
  late final choices = widget.categories
      .where(
        (category) =>
            category['id'] != null &&
            (widget.initial != null
                ? category['id'] == widget.initial!['category_id']
                : !widget.budgets.any(
                    (b) => b['category_id'] == category['id'],
                  )),
      )
      .toList();
  late String? categoryId = choices.isEmpty
      ? null
      : choices.first['id'] as String;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> save({bool remove = false}) async {
    if (busy ||
        categoryId == null ||
        !remove && !form.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (remove) {
        await widget.api.removeBudget(widget.month, categoryId!);
      } else {
        final parts = amount.text.trim().split('.');
        final exact =
            '${parts[0]}.${(parts.length == 1 ? '' : parts[1]).padRight(2, '0')}';
        await widget.api.saveBudget(widget.month, categoryId!, exact);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        widget.onExpired();
        return;
      }
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.initial == null ? 'Set' : 'Edit'} budget · ${widget.month}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'This category limit covers all your cards for the selected month.',
              ),
              const SizedBox(height: 16),
              if (choices.isEmpty)
                const Text(
                  'Every category already has a budget. Close this sheet to edit an existing budget.',
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Budget category',
                  ),
                  items: [
                    for (final category in choices)
                      DropdownMenuItem(
                        value: category['id'] as String,
                        child: Text(category['name'] as String),
                      ),
                  ],
                  onChanged: busy || widget.initial != null
                      ? null
                      : (v) => setState(() => categoryId = v),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amount,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Monthly limit (PKR)',
                  ),
                  validator: (v) =>
                      RegExp(
                            r'^[0-9]{1,12}(\.[0-9]{1,2})?$',
                          ).hasMatch((v ?? '').trim()) &&
                          RegExp(r'[1-9]').hasMatch(v ?? '')
                      ? null
                      : 'Enter a positive limit with up to two decimal places.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : () => save(),
                  child: Text(busy ? 'Saving…' : 'Save budget'),
                ),
                if (widget.initial != null)
                  TextButton(
                    onPressed: busy ? null : () => save(remove: true),
                    child: const Text('Remove budget'),
                  ),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
