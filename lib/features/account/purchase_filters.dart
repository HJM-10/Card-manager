import 'package:flutter/material.dart';

import '../../data/spendtrail_api.dart';

const uncategorizedValue = 'uncategorized';

class PurchaseFilters {
  const PurchaseFilters({
    this.cardId,
    this.category,
    this.dates,
    this.status,
    this.kind,
  });
  final String? status, kind;
  final String? cardId;
  // null means all categories; the sentinel selects records without a category.
  final String? category;
  final DateTimeRange? dates;
  bool get active =>
      cardId != null ||
      category != null ||
      dates != null ||
      status != null ||
      kind != null;
  DateTime? get before => dates == null
      ? null
      : DateTime(dates!.end.year, dates!.end.month, dates!.end.day + 1);
}

String calendarDate(DateTime value) => value.toIso8601String().substring(0, 10);

class PurchaseFiltersSheet extends StatefulWidget {
  const PurchaseFiltersSheet({
    super.key,
    required this.api,
    required this.initial,
    required this.onExpired,
  });
  final SpendTrailApi api;
  final PurchaseFilters initial;
  final VoidCallback onExpired;
  @override
  State<PurchaseFiltersSheet> createState() => _PurchaseFiltersSheetState();
}

class _PurchaseFiltersSheetState extends State<PurchaseFiltersSheet> {
  List<Map<String, dynamic>> cards = [], categories = [];
  late String? cardId = widget.initial.cardId,
      category = widget.initial.category;
  late DateTimeRange? dates = widget.initial.dates;
  late String? status = widget.initial.status, kind = widget.initial.kind;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Future.wait([
        widget.api.cards(includeArchived: true),
        widget.api.categories(),
      ]);
      if (mounted) {
        setState(() {
          cards = result[0];
          categories = result[1];
        });
      }
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

  Future<void> chooseDates() async {
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: dates,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Purchase dates (inclusive)',
    );
    if (range != null && mounted) setState(() => dates = range);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Filter purchases',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (error != null) ...[
              Text(error!),
              TextButton(onPressed: load, child: const Text('Retry')),
            ] else ...[
              DropdownButtonFormField<String>(
                key: ValueKey('card-$cardId'),
                initialValue: cardId ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Filter by card'),
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
                onChanged: (v) => setState(() => cardId = v == '' ? null : v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('category-$category'),
                initialValue: category ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Filter by category',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All categories'),
                  ),
                  const DropdownMenuItem(
                    value: uncategorizedValue,
                    child: Text('Uncategorized'),
                  ),
                  for (final item in categories)
                    DropdownMenuItem(
                      value: item['id'] as String,
                      child: Text(
                        item['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => category = v == '' ? null : v),
              ),
              const SizedBox(height: 16),
              for (final isStatus in [true, false])
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    '${isStatus ? 'status' : 'kind'}-${isStatus ? status : kind}',
                  ),
                  initialValue: (isStatus ? status : kind) ?? '',
                  decoration: InputDecoration(
                    labelText: isStatus ? 'Filter by status' : 'Filter by type',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(isStatus ? 'All statuses' : 'All types'),
                    ),
                    for (final value
                        in isStatus
                            ? ['approved', 'declined']
                            : ['purchase', 'refund'])
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          '${value[0].toUpperCase()}${value.substring(1)}',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    if (isStatus) {
                      status = v == '' ? null : v;
                    } else {
                      kind = v == '' ? null : v;
                    }
                  }),
                ),
              TextButton.icon(
                onPressed: chooseDates,
                icon: const Icon(Icons.date_range),
                label: Text(
                  dates == null
                      ? 'Choose date range'
                      : '${calendarDate(dates!.start)} to ${calendarDate(dates!.end)}',
                ),
              ),
              const Text(
                'Dates include both days in your device’s local time.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  PurchaseFilters(
                    cardId: cardId,
                    category: category,
                    dates: dates,
                    status: status,
                    kind: kind,
                  ),
                ),
                child: const Text('Apply filters'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  cardId = null;
                  category = null;
                  dates = null;
                  status = null;
                  kind = null;
                }),
                child: const Text('Reset filters'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<Map<String, dynamic>?> showNewCategory(
  BuildContext context,
  SpendTrailApi api,
  VoidCallback onExpired,
) => showDialog<Map<String, dynamic>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _NewCategory(api: api, onExpired: onExpired),
);

class CategorySelector extends StatelessWidget {
  const CategorySelector({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
    required this.onCreate,
  });
  final List<Map<String, dynamic>> categories;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final VoidCallback? onCreate;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey(value),
        initialValue: value ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Category'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Uncategorized')),
          for (final item in categories)
            DropdownMenuItem(
              value: item['id'] as String,
              child: Text(
                item['name'] as String,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onChanged == null
            ? null
            : (v) => onChanged!(v == '' ? null : v),
      ),
      TextButton(onPressed: onCreate, child: const Text('New category')),
    ],
  );
}

class _NewCategory extends StatefulWidget {
  const _NewCategory({required this.api, required this.onExpired});
  final SpendTrailApi api;
  final VoidCallback onExpired;
  @override
  State<_NewCategory> createState() => _NewCategoryState();
}

class _NewCategoryState extends State<_NewCategory> {
  final name = TextEditingController(), form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final category = await widget.api.createCategory(name.text);
      if (mounted) Navigator.pop(context, category);
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
    child: AlertDialog(
      title: const Text('New category'),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              enabled: !busy,
              maxLength: 50,
              decoration: const InputDecoration(labelText: 'Category name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a category name.' : null,
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving…' : 'Create category'),
        ),
      ],
    ),
  );
}
