import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/spendtrail_api.dart';
import 'purchase_filters.dart';

String _date(String value) =>
    DateTime.parse(value).toLocal().toString().substring(0, 16);

/// Account purchases are fetched from the API, independently of local demo activity.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({
    super.key,
    required this.api,
    required this.onExpired,
  });
  final SpendTrailApi api;
  final VoidCallback onExpired;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final records = <Map<String, dynamic>>[];
  bool loading = false, more = true;
  bool retryReset = true;
  String? error;
  final search = TextEditingController();
  String appliedSearch = '';
  PurchaseFilters filters = const PurchaseFilters();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> filter() async {
    final result = await showModalBottomSheet<PurchaseFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PurchaseFiltersSheet(
        api: widget.api,
        initial: filters,
        onExpired: widget.onExpired,
      ),
    );
    if (result != null && mounted) {
      setState(() => filters = result);
      await load(reset: true);
    }
  }

  void applySearch() {
    if (loading) return;
    appliedSearch = search.text.trim();
    load(reset: true);
  }

  Future<void> detail(Map<String, dynamic> record) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PurchaseDetail(
          api: widget.api,
          id: record['id'] as String,
          onExpired: widget.onExpired,
        ),
      ),
    );
    if (mounted) await load(reset: true);
  }

  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (loading) return;
    retryReset = reset;
    setState(() {
      loading = true;
      error = null;
      if (reset) records.clear();
    });
    try {
      final page = await widget.api.purchases(
        offset: reset ? 0 : records.length,
        search: appliedSearch,
        cardId: filters.cardId,
        categoryId: filters.category == uncategorizedValue
            ? null
            : filters.category,
        uncategorized: filters.category == uncategorizedValue,
        occurredFrom: filters.dates?.start,
        occurredBefore: filters.before,
      );
      if (!mounted) return;
      setState(() {
        if (reset) records.clear();
        records.addAll(page);
        more = page.length == 25;
      });
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

  Future<void> add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _PurchaseEditor(api: widget.api, onExpired: widget.onExpired),
      ),
    );
    if (saved == true && mounted) await load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Account purchases'),
      actions: [
        IconButton(
          tooltip: 'Refresh purchases',
          onPressed: loading ? null : () => load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: RefreshIndicator(
          onRefresh: () => load(reset: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Manual purchases saved to your account · PKR'),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                enabled: !loading,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: 'Search merchants',
                  counterText: '',
                  suffixIcon: IconButton(
                    tooltip: 'Search purchases',
                    onPressed: loading ? null : applySearch,
                    icon: const Icon(Icons.search),
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => applySearch(),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: loading ? null : filter,
                    icon: const Icon(Icons.filter_list),
                    label: Text(filters.active ? 'Filters applied' : 'Filters'),
                  ),
                  if (filters.active || appliedSearch.isNotEmpty)
                    TextButton(
                      onPressed: loading
                          ? null
                          : () {
                              setState(() {
                                filters = const PurchaseFilters();
                                appliedSearch = '';
                                search.clear();
                              });
                              load(reset: true);
                            },
                      child: const Text('Clear search & filters'),
                    ),
                ],
              ),
              if (filters.dates != null)
                Text(
                  'Dates: ${calendarDate(filters.dates!.start)} to ${calendarDate(filters.dates!.end)}',
                ),
              FilledButton.icon(
                onPressed: loading ? null : add,
                icon: const Icon(Icons.add),
                label: const Text('Record purchase'),
              ),
              if (!loading && error == null && records.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    // Applied filters can legitimately return an empty page.
                    'No account purchases match. Clear filters or record a purchase.',
                  ),
                ),
              for (final record in records)
                Card(
                  child: ListTile(
                    title: Text(record['merchant'] as String),
                    subtitle: Text(
                      '${_date(record['occurred_at'] as String)} · ${record['channel']}\n${record['category'] ?? 'Uncategorized'}',
                    ),
                    trailing: Text('PKR ${record['amount']}'),
                    onTap: () => detail(record),
                  ),
                ),
              if (loading) const Center(child: CircularProgressIndicator()),
              if (error != null) ...[
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: () => load(reset: retryReset),
                  child: const Text('Retry'),
                ),
              ] else if (!loading && more && records.isNotEmpty)
                TextButton(onPressed: load, child: const Text('Load more')),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PurchaseEditor extends StatefulWidget {
  const _PurchaseEditor({required this.api, required this.onExpired});
  final SpendTrailApi api;
  final VoidCallback onExpired;
  @override
  State<_PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<_PurchaseEditor> {
  final form = GlobalKey<FormState>();
  final merchant = TextEditingController(), amount = TextEditingController();
  List<Map<String, dynamic>> cards = [];
  List<Map<String, dynamic>> categories = [];
  String? categoryId;
  String? cardId, error;
  String channel = 'pos';
  DateTime occurredAt = DateTime.now();
  bool loading = true, busy = false;
  // Freeze the entire request after the first attempt so ambiguous network
  // failures can be retried without duplicating a committed purchase.
  Map<String, dynamic>? pending;

  @override
  void initState() {
    super.initState();
    loadCards();
  }

  void handle(ApiException e) {
    if (!mounted) return;
    if (e.unauthorized) {
      widget.onExpired();
      return;
    }
    setState(() => error = e.message);
  }

  Future<void> loadCards() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Future.wait([
        widget.api.cards(),
        widget.api.categories(),
      ]);
      if (mounted) {
        setState(() {
          cards = result[0];
          categories = result[1];
          cardId = cards.isEmpty ? null : cards.first['id'] as String;
        });
      }
    } on ApiException catch (e) {
      handle(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (pending == null) {
      final random = Random.secure();
      final bytes = List.generate(16, (_) => random.nextInt(256));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final parts = amount.text.trim().split('.');
      pending = {
        'card_id': cardId,
        'merchant': merchant.text.trim(),
        'amount':
            '${parts[0]}.${(parts.length == 1 ? '' : parts[1]).padRight(2, '0')}',
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'channel': channel,
        'category_id': categoryId,
        'source_reference':
            '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}',
      };
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.recordPurchase(pending!);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      // Definite rejections did not commit; allow correcting the form.
      if (e.statusCode != null &&
          e.statusCode! >= 400 &&
          e.statusCode! < 500 &&
          e.statusCode != 408) {
        pending = null;
      }
      handle(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: occurredAt,
      firstDate: DateTime(2000, 1, 2),
      lastDate: DateTime(2100, 12, 30),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(occurredAt),
    );
    if (time != null && mounted) {
      setState(
        () => occurredAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  @override
  void dispose() {
    merchant.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editable = !busy && pending == null;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Record purchase')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('Record a manual purchase. No money moves.'),
                  const SizedBox(height: 16),
                  if (loading)
                    const Center(child: CircularProgressIndicator())
                  else if (cards.isEmpty) ...[
                    const Text(
                      'Add an account card profile before recording a purchase.',
                    ),
                    TextButton(
                      onPressed: loadCards,
                      child: const Text('Reload cards'),
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      initialValue: cardId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Account card',
                      ),
                      items: [
                        for (final card in cards)
                          DropdownMenuItem(
                            value: card['id'] as String,
                            child: Text(
                              '${card['label']} •••• ${card['last4']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: editable
                          ? (v) => setState(() => cardId = v)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: merchant,
                      enabled: editable,
                      maxLength: 100,
                      decoration: const InputDecoration(labelText: 'Merchant'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Enter a merchant.' : null,
                    ),
                    TextFormField(
                      controller: amount,
                      enabled: editable,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount (PKR)',
                      ),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (!RegExp(
                              r'^[0-9]{1,12}(\.[0-9]{1,2})?$',
                            ).hasMatch(value) ||
                            !RegExp(r'[1-9]').hasMatch(value)) {
                          return 'Enter a positive amount with up to two decimal places.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CategorySelector(
                      categories: categories,
                      value: categoryId,
                      onChanged: editable
                          ? (v) => setState(() => categoryId = v)
                          : null,
                      onCreate: editable
                          ? () async {
                              final result = await showNewCategory(
                                context,
                                widget.api,
                                widget.onExpired,
                              );
                              if (result != null && mounted) {
                                setState(() {
                                  categories.add(result);
                                  categoryId = result['id'] as String;
                                });
                              }
                            }
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: channel,
                      decoration: const InputDecoration(labelText: 'Channel'),
                      items: const [
                        DropdownMenuItem(
                          value: 'pos',
                          child: Text('Point of sale'),
                        ),
                        DropdownMenuItem(
                          value: 'online',
                          child: Text('Online'),
                        ),
                      ],
                      onChanged: editable
                          ? (v) => setState(() => channel = v!)
                          : null,
                    ),
                    TextButton.icon(
                      onPressed: editable ? chooseDate : null,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        'Purchase date: ${_date(occurredAt.toIso8601String())}',
                      ),
                    ),
                    if (pending != null && !busy)
                      const Text(
                        'Retry sends the same purchase safely. Details are locked for this attempt.',
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : save,
                      child: Text(
                        busy
                            ? 'Saving…'
                            : pending != null
                            ? 'Retry save'
                            : 'Save purchase',
                      ),
                    ),
                  ],
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PurchaseDetail extends StatefulWidget {
  const _PurchaseDetail({
    required this.api,
    required this.id,
    required this.onExpired,
  });
  final SpendTrailApi api;
  final String id;
  final VoidCallback onExpired;
  @override
  State<_PurchaseDetail> createState() => _PurchaseDetailState();
}

class _PurchaseDetailState extends State<_PurchaseDetail> {
  Map<String, dynamic>? record;
  String? error;
  bool loading = true;
  Future<void> editCategory() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CategoryEditor(
        api: widget.api,
        record: record!,
        onExpired: widget.onExpired,
      ),
    );
    if (result != null && mounted) setState(() => record = result);
  }

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
      final result = await widget.api.purchase(widget.id);
      if (mounted) setState(() => record = result);
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Purchase details')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (error != null) ...[
          Text(error!),
          TextButton(onPressed: load, child: const Text('Retry')),
        ] else if (record != null) ...[
          Text(
            record!['merchant'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            'PKR ${record!['amount']}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(_date(record!['occurred_at'] as String)),
          const SizedBox(height: 12),
          Text('Category: ${record!['category'] ?? 'Uncategorized'}'),
          TextButton.icon(
            onPressed: editCategory,
            icon: const Icon(Icons.category_outlined),
            label: const Text('Change category'),
          ),
          for (final (key, label) in [
            ('status', 'Status'),
            ('channel', 'Channel'),
            ('kind', 'Type'),
            ('source', 'Recorded by'),
          ])
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('$label: ${record![key]}'),
            ),
        ],
      ],
    ),
  );
}

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({
    required this.api,
    required this.record,
    required this.onExpired,
  });
  final SpendTrailApi api;
  final Map<String, dynamic> record;
  final VoidCallback onExpired;
  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  List<Map<String, dynamic>> categories = [];
  late String? selected = widget.record['category_id'] as String?;
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  void handle(ApiException e) {
    if (!mounted) return;
    if (e.unauthorized) {
      widget.onExpired();
      return;
    }
    setState(() => error = e.message);
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.categories();
      if (mounted) setState(() => categories = result);
    } on ApiException catch (e) {
      handle(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.categorizePurchase(
        widget.record['id'] as String,
        selected,
      );
      if (mounted) Navigator.pop(context, result);
    } on ApiException catch (e) {
      handle(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Change category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (loading)
                const Center(child: CircularProgressIndicator())
              else if (categories.isEmpty && error != null)
                TextButton(onPressed: load, child: const Text('Retry'))
              else ...[
                CategorySelector(
                  categories: categories,
                  value: selected,
                  onChanged: busy ? null : (v) => setState(() => selected = v),
                  onCreate: busy
                      ? null
                      : () async {
                          final result = await showNewCategory(
                            context,
                            widget.api,
                            widget.onExpired,
                          );
                          if (result != null && mounted) {
                            setState(() {
                              categories.add(result);
                              selected = result['id'] as String;
                            });
                          }
                        },
                ),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Saving…' : 'Save category'),
                ),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
