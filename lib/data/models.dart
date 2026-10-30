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

  Map<String, Object> toJson() => {
    'id': id, 'brand': brand.name, 'last4': last4, 'holder': holder,
    'expiry': expiry, 'balance': balance,
    'gradient': gradient.map((c) => c.toARGB32()).toList(),
  };

  factory CreditCard.fromJson(Map<String, dynamic> json) => CreditCard(
    id: json['id'] as String,
    brand: CardBrand.values.byName(json['brand'] as String),
    last4: json['last4'] as String, holder: json['holder'] as String,
    expiry: json['expiry'] as String, balance: (json['balance'] as num).toDouble(),
    gradient: (json['gradient'] as List).map((c) => Color(c as int)).toList(),
  );
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
