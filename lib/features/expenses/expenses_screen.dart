import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}
class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String query = '', category = 'All', card = 'All';
  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    final entries = ref.watch(expensesProvider).where((e) =>
      e.title.toLowerCase().contains(query.toLowerCase()) &&
      (category == 'All' || e.category == category) &&
      (card == 'All' || e.cardId == card)).toList();
    final filterCards = <String, String>{'All': 'All cards', for (final c in cards) c.id: '•••• ${c.last4}'};
    for (final e in ref.watch(expensesProvider)) {
      if (e.cardId != null) filterCards.putIfAbsent(e.cardId!, () => 'Removed card');
    }
    return Scaffold(appBar: AppBar(title: const Text('Expenses & activity')), body: ListView(padding: const EdgeInsets.all(20), children: [
      TextField(decoration: const InputDecoration(labelText: 'Search activity', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => query = v)),
      DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Category'), items: ['All', ...expenseCategories].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => category = v!)),
      DropdownButtonFormField<String>(initialValue: filterCards.containsKey(card) ? card : 'All', decoration: const InputDecoration(labelText: 'Card'), items: filterCards.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) => setState(() => card = v!)),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: () => showExpenseEditor(context), icon: const Icon(Icons.add), label: const Text('Add expense')),
      if (entries.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No activity found. Add an expense or change your filters.')),
      for (final e in entries) Card(child: ListTile(
        leading: Icon(e.icon), title: Text(e.title), subtitle: Text('${e.timestamp}${e.kind == 'expense' ? '' : ' · Demo ${e.kind}'}'),
        trailing: Text(ref.watch(moneyProvider)(e.amount)), onTap: () => showExpenseEditor(context, expense: e),
      )),
    ]));
  }
}

Future<void> showExpenseEditor(BuildContext context, {Expense? expense}) => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _ExpenseEditor(expense: expense));

class _ExpenseEditor extends ConsumerStatefulWidget {
  const _ExpenseEditor({this.expense});
  final Expense? expense;
  @override
  ConsumerState<_ExpenseEditor> createState() => _ExpenseEditorState();
}
class _ExpenseEditorState extends ConsumerState<_ExpenseEditor> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.expense?.title);
  late final amount = TextEditingController(text: widget.expense?.amount.toStringAsFixed(2));
  late String category = widget.expense?.category ?? 'Other';
  late String? card = widget.expense?.cardId;
  late DateTime date = widget.expense?.date ?? DateTime.now();
  bool saving = false;
  String? error;
  @override
  void dispose() { title.dispose(); amount.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    final cardItems = <String, String>{'': 'No card', for (final c in cards) c.id: '${c.brand.name} •••• ${c.last4}'};
    if (card != null) cardItems.putIfAbsent(card!, () => 'Removed card');
    return SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom), child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.expense == null ? 'Add expense' : 'Edit activity', style: Theme.of(context).textTheme.titleLarge),
      TextFormField(controller: title, maxLength: 80, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter a title.' : null),
      TextFormField(controller: amount, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) => parseAmountCents(v ?? '') == null ? 'Enter an amount above zero, with up to two decimals.' : null),
      DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Category'), items: expenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: saving ? null : (v) => setState(() => category = v!)),
      DropdownButtonFormField<String>(initialValue: card ?? '', decoration: const InputDecoration(labelText: 'Card'), items: cardItems.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: saving ? null : (v) => setState(() => card = v == '' ? null : v)),
      TextButton.icon(icon: const Icon(Icons.calendar_today), label: Text('Date: ${date.day}/${date.month}/${date.year}'), onPressed: saving ? null : () async {
        final chosen = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime.now());
        if (chosen != null && mounted) setState(() => date = chosen);
      }),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      FilledButton(onPressed: saving ? null : () async {
        if (!form.currentState!.validate()) return;
        setState(() { saving = true; error = null; });
        try {
          await ref.read(expensesProvider.notifier).upsert(Expense(id: widget.expense?.id ?? DateTime.now().microsecondsSinceEpoch.toString(), title: title.text.trim(), date: date, cents: parseAmountCents(amount.text)!, category: category, cardId: card, kind: widget.expense?.kind ?? 'expense'));
          if (context.mounted) Navigator.pop(context);
        } catch (_) { if (mounted) setState(() { saving = false; error = 'Could not save. Check your card selection and try again.'; }); }
      }, child: Text(saving ? 'Saving…' : 'Save')),
      if (widget.expense != null) TextButton(onPressed: saving ? null : () async {
        setState(() => saving = true);
        try { await ref.read(expensesProvider.notifier).remove(widget.expense!.id); if (context.mounted) Navigator.pop(context); }
        catch (_) { if (mounted) setState(() { saving = false; error = 'Could not delete. Please try again.'; }); }
      }, child: const Text('Delete activity')),
    ])))));
  }
}
