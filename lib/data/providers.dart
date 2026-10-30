import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/card_utils.dart';
import 'models.dart';

/// Cards in stack order: index 0 is the back, the last item is the front.
class CardsNotifier extends Notifier<List<CreditCard>> {
  @override
  List<CreditCard> build() => const [
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

  /// Moves the tapped card to the front of the stack.
  void bringToFront(String id) {
    final card = state.firstWhere((c) => c.id == id);
    state = [...state.where((c) => c.id != id), card];
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
    state = [
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
    ];
  }
}

final cardsProvider =
    NotifierProvider<CardsNotifier, List<CreditCard>>(CardsNotifier.new);

final expensesProvider = Provider<List<Expense>>(
  (ref) => const [
    Expense(
      title: 'House Rent',
      timestamp: '10:00 am 15 March, 2025',
      amount: 300,
      icon: Icons.home_outlined,
    ),
    Expense(
      title: 'Internet Bill',
      timestamp: '12:30 pm 15 March, 2025',
      amount: 85,
      icon: Icons.wifi_rounded,
    ),
    Expense(
      title: 'Groceries',
      timestamp: '09:30 am 14 March, 2025',
      amount: 240,
      icon: Icons.shopping_cart_outlined,
    ),
    Expense(
      title: 'Electricity',
      timestamp: '06:15 pm 12 March, 2025',
      amount: 120,
      icon: Icons.bolt_outlined,
    ),
    Expense(
      title: 'Gym Membership',
      timestamp: '08:00 am 10 March, 2025',
      amount: 45,
      icon: Icons.fitness_center_rounded,
    ),
    Expense(
      title: 'Streaming',
      timestamp: '09:45 pm 08 March, 2025',
      amount: 15.99,
      icon: Icons.play_circle_outline_rounded,
    ),
  ],
);

/// Selected bottom-nav tab.
class TabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final tabProvider = NotifierProvider<TabNotifier, int>(TabNotifier.new);
