import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/data/statistics.dart';

void main() {
  test('statistics group spending and cross year boundaries', () {
    Expense entry(String id, int month, int cents, {String kind = 'expense'}) =>
        Expense(
          id: id,
          title: id,
          date: DateTime(2026, month, 1),
          cents: cents,
          category: 'Food',
          kind: kind,
        );
    final summary = SpendingSummary([
      entry('a', 1, 1234),
      entry('b', 1, 100),
      entry('c', 1, 900, kind: 'request'),
      entry('d', 1, 800, kind: 'topUp'),
      entry('e', 0, 500),
    ], DateTime(2026, 1));
    expect(summary.totalCents, 1334);
    expect(summary.count, 2);
    expect(summary.categories['Food'], 1334);
    expect(summary.monthly[DateTime(2025, 12)], 500);
    expect(summary.monthly.length, 6);
  });
}
