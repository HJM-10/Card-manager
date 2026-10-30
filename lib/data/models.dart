import 'package:flutter/material.dart';

import '../core/utils/card_utils.dart';

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
    'id': id,
    'brand': brand.name,
    'last4': last4,
    'holder': holder,
    'expiry': expiry,
    'balance': balance,
    'gradient': gradient.map((c) => c.toARGB32()).toList(),
  };

  factory CreditCard.fromJson(Map<String, dynamic> json) => CreditCard(
    id: json['id'] as String,
    brand: CardBrand.values.byName(json['brand'] as String),
    last4: json['last4'] as String,
    holder: json['holder'] as String,
    expiry: json['expiry'] as String,
    balance: (json['balance'] as num).toDouble(),
    gradient: (json['gradient'] as List).map((c) => Color(c as int)).toList(),
  );
}

class Expense {
  const Expense({
    required this.id,
    required this.title,
    required this.date,
    required this.cents,
    required this.category,
    this.cardId,
    this.kind = 'expense',
  });

  final String id;
  final String title;
  final DateTime date;
  final int cents;
  final String category;
  final String? cardId;
  final String kind;
  bool get isSpending => kind == 'expense' || kind == 'send';
  double get amount => cents / 100;
  String get timestamp => '${date.day}/${date.month}/${date.year} · $category';
  IconData get icon => switch (category) {
    'Housing' => Icons.home_outlined,
    'Food' => Icons.shopping_cart_outlined,
    'Bills' => Icons.bolt_outlined,
    'Transport' => Icons.directions_bus_outlined,
    'Leisure' => Icons.movie_outlined,
    _ => Icons.receipt_long_outlined,
  };
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'date': date.toIso8601String(),
    'cents': cents,
    'category': category,
    'cardId': cardId,
    'kind': kind,
  };
  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    title: json['title'] as String,
    date: DateTime.parse(json['date'] as String),
    cents: json['cents'] as int,
    category: json['category'] as String,
    cardId: json['cardId'] as String?,
    kind: json['kind'] as String? ?? 'expense',
  );
}
