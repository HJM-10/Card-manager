import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/core/utils/card_utils.dart';

void main() {
  group('card utils', () {
    test('detects brands', () {
      expect(detectBrand('4123 4567'), CardBrand.visa);
      expect(detectBrand('5412'), CardBrand.mastercard);
      expect(detectBrand('2221 0000'), CardBrand.mastercard);
      expect(detectBrand('3714'), CardBrand.unknown);
    });

    test('formats card number in groups of four', () {
      final out = CardNumberFormatter().formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '4123456786712323999'),
      );
      expect(out.text, '4123 4567 8671 2323');
    });

    test('formats expiry with slash', () {
      final out = ExpiryFormatter().formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '1233'),
      );
      expect(out.text, '12/33');
    });

    test('validates expiry', () {
      final now = DateTime(2026, 10, 23);
      expect(isExpiryValid('12/33', now: now), isTrue);
      expect(isExpiryValid('09/26', now: now), isFalse);
      expect(isExpiryValid('13/30', now: now), isFalse);
    });

    test('formats money', () {
      expect(formatMoney(56782.8), r'$56,782.80');
      expect(formatMoney(85), r'$85.00');
    });

    test('luhn', () {
      expect(passesLuhn('4242 4242 4242 4242'), isTrue);
      expect(passesLuhn('4123 4567 8671 2323'), isFalse);
    });
  });
}
