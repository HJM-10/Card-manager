import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';

class DemoActionScreen extends ConsumerStatefulWidget {
  const DemoActionScreen({super.key, required this.action});
  final String action;
  @override
  ConsumerState<DemoActionScreen> createState() => _DemoActionScreenState();
}

class _DemoActionScreenState extends ConsumerState<DemoActionScreen> {
  final form = GlobalKey<FormState>();
  final person = TextEditingController();
  final amount = TextEditingController();
  String? cardId;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    person.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsProvider);
    final selected = cards.any((c) => c.id == cardId)
        ? cardId
        : cards.lastOrNull?.id;
    final isTopUp = widget.action == 'TopUp';
    return Scaffold(
      appBar: AppBar(title: Text('Demo ${widget.action}')),
      body: SafeArea(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Simulation only. This records demo activity on this device. No money moves and no message is sent.',
                  ),
                ),
              ),
              if (cards.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Add a test card in Cards before using this action.',
                  ),
                ),
              if (cards.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Demo balance: ${ref.watch(moneyProvider)(ref.watch(demoBalanceProvider(selected!)))}',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Card'),
                  items: cards
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.brand.name} •••• ${c.last4}'),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => cardId = v),
                ),
                TextFormField(
                  controller: person,
                  enabled: !busy,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: isTopUp
                        ? 'Source label'
                        : widget.action == 'Request'
                        ? 'Request from'
                        : 'Recipient',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter a name or label.'
                      : null,
                ),
                TextFormField(
                  controller: amount,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'Amount (${ref.watch(settingsProvider).currency})',
                  ),
                  validator: (v) => parseAmountCents(v ?? '') == null
                      ? 'Enter a positive amount with up to two decimals.'
                      : null,
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) return;
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          final cents = parseAmountCents(amount.text)!;
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: Text(
                                'Confirm demo ${widget.action.toLowerCase()}',
                              ),
                              content: Text(
                                '${ref.read(moneyProvider)(cents / 100)} · ${person.text.trim()}\nThis creates a simulated activity entry.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('Confirm demo'),
                                ),
                              ],
                            ),
                          );
                          if (!mounted) return;
                          if (confirmed != true) {
                            setState(() => busy = false);
                            return;
                          }
                          try {
                            await ref
                                .read(expensesProvider.notifier)
                                .upsert(
                                  Expense(
                                    id: DateTime.now().microsecondsSinceEpoch
                                        .toString(),
                                    title:
                                        '${widget.action}: ${person.text.trim()}',
                                    date: DateTime.now(),
                                    cents: cents,
                                    category: 'Other',
                                    cardId: selected,
                                    kind: switch (widget.action) {
                                      'Send' => 'send',
                                      'Request' => 'request',
                                      _ => 'topUp',
                                    },
                                  ),
                                );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  widget.action == 'Request'
                                      ? 'Demo request recorded as pending. No request was sent.'
                                      : 'Demo ${widget.action.toLowerCase()} recorded.',
                                ),
                              ),
                            );
                            Navigator.pop(context);
                          } catch (_) {
                            if (mounted) {
                              setState(() {
                                busy = false;
                                error =
                                    'Could not record activity. Check your card and try again.';
                              });
                            }
                          }
                        },
                  child: Text(
                    busy
                        ? 'Please wait…'
                        : 'Review demo ${widget.action.toLowerCase()}',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
