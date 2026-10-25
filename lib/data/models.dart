import 'package:flutter/material.dart';

import '../../core/utils/card_utils.dart';

class CreditCard {
  const CreditCard({
    required this.id,
    required this.brand,
    required this.last4,
    required this.holder,
    required this.expiry,
    required this.balance,
    required this.gradient,
  });

  final String id;
  final CardBrand brand;
  final String last4;
  final String holder;
  final String expiry;
  final double balance;
  final List<Color> gradient;
}

class Expense {
  const Expense({
    required this.title,
    required this.timestamp,
    required this.amount,
    required this.icon,
  });

  final String title;
  final String timestamp;
  final double amount;
  final IconData icon;
}
