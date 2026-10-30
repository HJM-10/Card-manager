import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers.dart';
import '../../data/models.dart';
import '../../data/settings.dart';
import '../add_card/add_card_sheet.dart';

class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
        children: [
          Text('Your cards', style: Theme.of(context).textTheme.headlineMedium),
          const Text('The default card appears at the front of your wallet.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => showAddCardSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Card'),
          ),
          if (cards.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No cards yet. Add your first test card to get started.',
              ),
            ),
          for (final card in cards.reversed)
            Card(
              child: ListTile(
                leading: const Icon(Icons.credit_card),
                title: Text(
                  '${card.brand.name.toUpperCase()} •••• ${card.last4}',
                ),
                subtitle: Text(
                  'Expires ${card.expiry}${card.id == cards.last.id ? ' · Default' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _details(context, ref, card),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _details(
    BuildContext context,
    WidgetRef ref,
    CreditCard card,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${card.brand.name.toUpperCase()} •••• ${card.last4}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Holder: ${card.holder}\nExpiry: ${card.expiry}\nDemo balance: ${ref.read(moneyProvider)(ref.read(demoBalanceProvider(card.id)))}',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await ref
                        .read(cardsProvider.notifier)
                        .bringToFront(card.id);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: const Text('Make default'),
                ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: sheetContext,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Remove card?'),
                        content: const Text(
                          'This removes the card from this demo wallet.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    try {
                      await ref.read(cardsProvider.notifier).remove(card.id);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    } catch (_) {
                      if (sheetContext.mounted) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not remove card. Please try again.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Remove card'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
