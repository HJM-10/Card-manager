import 'models.dart';

class SpendingSummary {
  SpendingSummary(Iterable<Expense> entries, DateTime month) {
    for (final e in entries.where((e) => e.isSpending)) {
      if (e.date.year == month.year && e.date.month == month.month) {
        totalCents += e.cents;
        count++;
        categories.update(
          e.category,
          (v) => v + e.cents,
          ifAbsent: () => e.cents,
        );
      }
    }
    for (var offset = 5; offset >= 0; offset--) {
      final date = DateTime(month.year, month.month - offset);
      monthly[date] = entries
          .where(
            (e) =>
                e.isSpending &&
                e.date.year == date.year &&
                e.date.month == date.month,
          )
          .fold(0, (sum, e) => sum + e.cents);
    }
  }
  int totalCents = 0;
  int count = 0;
  final categories = <String, int>{};
  final monthly = <DateTime, int>{};
}
