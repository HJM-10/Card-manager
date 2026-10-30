import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/card_utils.dart';
import 'models.dart';
import 'local_store.dart';

/// Cards in stack order: index 0 is the back, the last item is the front.
class CardsNotifier extends Notifier<List<CreditCard>> {
  @override
  List<CreditCard> build() {
    final store = ref.read(localStoreProvider);
    final saved = store.read('cards.v1');
    if (saved is List) {
      try {
        return saved.map((c) => CreditCard.fromJson(Map<String, dynamic>.from(c as Map))).toList();
      } catch (_) {
        store.warning.value = 'Saved cards could not be read. Demo cards are shown.';
      }
    }
    return const [
        CreditCard(
          id: 'c1',
          brand: CardBrand.visa,
          last4: '9312',
          holder: 'dailyflutterui',
          expiry: '11/27',
          balance: 12480.50,
          gradient: CardPalette.teal,
        ),
        CreditCard(
          id: 'c2',
          brand: CardBrand.mastercard,
          last4: '2585',
          holder: 'dailyflutterui',
          expiry: '04/28',
          balance: 3215.00,
          gradient: CardPalette.amber,
        ),
        CreditCard(
          id: 'c3',
          brand: CardBrand.visa,
          last4: '7845',
          holder: 'dailyflutterui',
          expiry: '08/26',
          balance: 56782.80,
          gradient: CardPalette.violet,
        ),
      ];
  }

  Future<void> _save(List<CreditCard> cards) async {
    await ref.read(localStoreProvider).write('cards.v1', cards.map((c) => c.toJson()).toList());
    state = cards;
  }

  Future<void> remove(String id) => _save(state.where((c) => c.id != id).toList());

  /// Moves the tapped card to the front of the stack.
  Future<void> bringToFront(String id) async {
    final card = state.firstWhere((c) => c.id == id);
    try {
      await _save([...state.where((c) => c.id != id), card]);
    } catch (_) { /* LocalStore exposes the save failure to the app. */ }
  }

  /// Simulates a network call, then adds the card at the front.
  Future<void> addCard({
    required String number,
    required String expiry,
  }) async {
    if (!isCardNumberValid(number) || !isExpiryValid(expiry)) {
      throw ArgumentError('Check the card number and expiry date.');
    }
    final last4 = number.replaceAll(RegExp(r'\D'), '').substring(12);
    if (state.any((c) => c.last4 == last4 && c.brand == detectBrand(number))) {
      throw StateError('A card with this network and last four digits already exists.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2400));
    final digits = number.replaceAll(RegExp(r'\D'), '');
    final gradient =
        CardPalette.forNewCards[state.length % CardPalette.forNewCards.length];
    await _save([
      ...state,
      CreditCard(
        id: 'c${DateTime.now().microsecondsSinceEpoch}',
        brand: detectBrand(digits),
        last4: digits.substring(digits.length - 4),
        holder: 'dailyflutterui',
        expiry: expiry,
        balance: 0,
        gradient: gradient,
      ),
    ]);
  }
}

final cardsProvider =
    NotifierProvider<CardsNotifier, List<CreditCard>>(CardsNotifier.new);

const expenseCategories = ['Housing', 'Food', 'Bills', 'Transport', 'Leisure', 'Other'];

class ExpensesNotifier extends Notifier<List<Expense>> {
  @override
  List<Expense> build() {
    final saved = ref.read(localStoreProvider).read('expenses.v1');
    if (saved is List) {
      try {
        return saved.map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } catch (_) {
        ref.read(localStoreProvider).warning.value = 'Saved expenses could not be read.';
      }
    }
    return [];
  }
  Future<void> upsert(Expense expense) async {
    if (expense.title.trim().isEmpty || expense.cents <= 0 || expense.cents > 99999999999) {
      throw ArgumentError('Enter a title and a positive amount.');
    }
    if (expense.cardId != null && !ref.read(cardsProvider).any((c) => c.id == expense.cardId)) {
      throw StateError('Choose a card that is still in your wallet.');
    }
    final next = [...state.where((e) => e.id != expense.id), expense]..sort((a, b) => b.date.compareTo(a.date));
    await ref.read(localStoreProvider).write('expenses.v1', next.map((e) => e.toJson()).toList());
    state = next;
  }
  Future<void> remove(String id) async {
    final next = state.where((e) => e.id != id).toList();
    await ref.read(localStoreProvider).write('expenses.v1', next.map((e) => e.toJson()).toList());
    state = next;
  }
}
final expensesProvider = NotifierProvider<ExpensesNotifier, List<Expense>>(ExpensesNotifier.new);

int? parseAmountCents(String input) {
  final match = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(input.trim());
  if (match == null) return null;
  final value = int.parse(match[1]!) * 100 + int.parse((match[2] ?? '').padRight(2, '0'));
  return value > 0 ? value : null;
}

/// Selected bottom-nav tab.
class TabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final tabProvider = NotifierProvider<TabNotifier, int>(TabNotifier.new);
