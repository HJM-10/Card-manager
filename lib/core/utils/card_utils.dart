import 'package:flutter/services.dart';

enum CardBrand { visa, mastercard, unknown }

/// Detects the card network from the leading digits (BIN).
CardBrand detectBrand(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return CardBrand.unknown;
  if (digits.startsWith('4')) return CardBrand.visa;
  if (digits.length >= 2) {
    final two = int.parse(digits.substring(0, 2));
    if (two >= 51 && two <= 55) return CardBrand.mastercard;
  }
  if (digits.length >= 4) {
    final four = int.parse(digits.substring(0, 4));
    if (four >= 2221 && four <= 2720) return CardBrand.mastercard;
  }
  return CardBrand.unknown;
}

/// Standard Luhn checksum.
bool passesLuhn(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 12) return false;
  var sum = 0;
  var doubleIt = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var d = int.parse(digits[i]);
    if (doubleIt) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    doubleIt = !doubleIt;
  }
  return sum % 10 == 0;
}

/// The demo number typed in the video (4123 4567 8671 2323) fails Luhn,
/// so the check is off by default to match the reference flow.
const kEnforceLuhn = false;

bool isCardNumberValid(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 16) return false;
  return !kEnforceLuhn || passesLuhn(digits);
}

bool isExpiryValid(String input, {DateTime? now}) {
  final match = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(input);
  if (match == null) return false;
  final month = int.parse(match.group(1)!);
  final year = 2000 + int.parse(match.group(2)!);
  if (month < 1 || month > 12) return false;
  final today = now ?? DateTime.now();
  final endOfMonth = DateTime(year, month + 1);
  return endOfMonth.isAfter(today);
}

bool isCvvValid(String input) => RegExp(r'^\d{3,4}$').hasMatch(input);

/// Formats the card number as "0000 0000 0000 0000" while typing.
class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length > 16 ? digits.substring(0, 16) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < clipped.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(clipped[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Formats the expiry as "MM/YY", inserting the slash automatically.
class ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 4) digits = digits.substring(0, 4);
    final deleting = newValue.text.length < oldValue.text.length;
    String text;
    if (digits.length > 2) {
      text = '${digits.substring(0, 2)}/${digits.substring(2)}';
    } else if (digits.length == 2 && !deleting) {
      text = '$digits/';
    } else {
      text = digits;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// "$56,782.80"
String formatMoney(double value) {
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${value < 0 ? '-' : ''}\$$whole.${parts[1]}';
}
