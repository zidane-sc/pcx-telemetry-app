import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/garage/expense_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

ExpenseEntry entry(String id, ExpenseCategory c, double amount, double odo,
        {DateTime? at}) =>
    ExpenseEntry(
      id: id,
      timestamp: at ?? DateTime(2026, 1, 1),
      category: c,
      amountIdr: amount,
      odometerKm: odo,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ExpenseEntry serialization', () {
    test('round-trips', () {
      final e = entry('a', ExpenseCategory.tires, 450000, 12345.6,
          at: DateTime(2026, 3, 14, 9, 30));
      final back = ExpenseEntry.fromJson(e.toJson())!;
      expect(back.id, 'a');
      expect(back.category, ExpenseCategory.tires);
      expect(back.amountIdr, 450000);
      expect(back.odometerKm, 12345.6);
      expect(back.timestamp, DateTime(2026, 3, 14, 9, 30));
    });

    test('returns null on a corrupt row instead of throwing', () {
      expect(ExpenseEntry.fromJson({'id': 1}), isNull);
      expect(ExpenseEntry.fromJson({'id': 'a', 'timestamp': 'x'}), isNull);
      expect(ExpenseEntry.fromJson({'id': 'a', 'timestamp': '2026-01-01'}),
          isNull, reason: 'missing amount');
      expect(
          ExpenseEntry.fromJson({
            'id': 'a',
            'timestamp': 'not-a-date',
            'amountIdr': 10.0,
          }),
          isNotNull,
          reason: 'an unparseable date must not lose the whole row');
    });

    test('an unknown category falls back rather than throwing', () {
      final e = ExpenseEntry.fromJson({
        'id': 'a',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'category': 'submarine',
        'amountIdr': 10.0,
        'odometerKm': 1.0,
      });
      expect(e!.category, ExpenseCategory.other);
    });
  });

  group('ExpenseLedger totals', () {
    test('sums the whole ledger', () async {
      final l = ExpenseLedger();
      await l.initialize();
      await l.add(category: ExpenseCategory.fuel, amountIdr: 50000, odometerKm: 100);
      await l.add(category: ExpenseCategory.service, amountIdr: 250000, odometerKm: 100);
      expect(l.totalIdr, 300000);
      expect(l.totalFor(ExpenseCategory.service), 250000);
    });

    test('removing an entry updates the total', () async {
      final l = ExpenseLedger();
      await l.initialize();
      final a = await l.add(
          category: ExpenseCategory.fuel, amountIdr: 50000, odometerKm: 100);
      expect(l.totalIdr, 50000);
      await l.remove(a.id);
      expect(l.totalIdr, 0.0);
      expect(l.entries, isEmpty);
    });

    test('entries are newest first', () async {
      final l = ExpenseLedger();
      await l.initialize();
      await l.add(category: ExpenseCategory.fuel, amountIdr: 1, odometerKm: 1);
      await l.add(category: ExpenseCategory.fuel, amountIdr: 2, odometerKm: 2);
      expect(l.entries.first.amountIdr, 2);
    });
  });

  group('ExpenseLedger.costPerKm', () {
    test('uses odometer delta, not the raw odometer reading', () async {
      // A bike already at 12,000 km. Dividing by the reading would claim the
      // spend happened over 12,000 km when it happened over 500.
      final l = ExpenseLedger();
      await l.initialize();
      await l.add(
          category: ExpenseCategory.fuel,
          amountIdr: 100000,
          odometerKm: 12000,
          at: null);
      await l.add(
          category: ExpenseCategory.service,
          amountIdr: 100000,
          odometerKm: 12500);

      // 200,000 over 500 km = 400/km
      expect(l.costPerKm(), closeTo(400.0, 0.01));
    });

    test('returns null with a single entry', () async {
      final l = ExpenseLedger();
      await l.initialize();
      await l.add(category: ExpenseCategory.fuel, amountIdr: 50000, odometerKm: 1000);
      expect(l.costPerKm(), isNull,
          reason: 'one spend is not a rate');
    });

    test('returns null when the window is too short to be meaningful', () async {
      final l = ExpenseLedger();
      await l.initialize();
      await l.add(category: ExpenseCategory.fuel, amountIdr: 50000, odometerKm: 1000);
      await l.add(category: ExpenseCategory.fuel, amountIdr: 50000, odometerKm: 1010);
      expect(l.costPerKm(), isNull,
          reason: '10 km apart says nothing about running cost');
    });

    test('sorts chronologically before taking first and last', () async {
          final l = ExpenseLedger();
          await l.initialize();
          // Same odometer span, opposite insertion order. Timestamp is what
          // decides which end is "first" — without sorting, the span would come out
          // negative whenever an older entry is at a higher odometer.
          await l.add(
            category: ExpenseCategory.fuel,
            amountIdr: 50000,
            odometerKm: 1500,
            at: DateTime(2026, 1, 2),
          );
          await l.add(
            category: ExpenseCategory.fuel,
            amountIdr: 50000,
            odometerKm: 1000,
            at: DateTime(2026, 1, 1),
          );

          // 100,000 over 500 km regardless of insertion order.
          expect(l.costPerKm(), closeTo(200.0, 0.01));
        });

        test('a since filter excludes older spend', () async {
          final l = ExpenseLedger();
          await l.initialize();
          await l.add(
            category: ExpenseCategory.service,
            amountIdr: 500000,
            odometerKm: 1000,
            at: DateTime(2026, 1, 1),
          );
          await l.add(
            category: ExpenseCategory.fuel,
            amountIdr: 50000,
            odometerKm: 2000,
            at: DateTime(2026, 2, 1),
          );

          // Only the fuel entry falls after the cut, so there is not enough
                // history to state a rate.
                expect(l.costPerKm(since: DateTime(2026, 1, 15)), isNull);

                // Widening the window brings the service entry back: 550,000 over
                // 1,000 km. The filter uses isAfter, so an entry timestamped exactly at
                // the cut is excluded -- the window must start strictly earlier.
                expect(l.costPerKm(since: DateTime(2025, 12, 31)), closeTo(550.0, 0.01));
              });

              test('an entry exactly at the since cutoff is excluded', () async {
                final l = ExpenseLedger();
                await l.initialize();
                await l.add(
                  category: ExpenseCategory.fuel,
                  amountIdr: 50000,
                  odometerKm: 1000,
                  at: DateTime(2026, 3, 1),
                );
                await l.add(
                  category: ExpenseCategory.fuel,
                  amountIdr: 50000,
                  odometerKm: 2000,
                  at: DateTime(2026, 3, 2),
                );

                // Cutoff == first entry's timestamp leaves only one entry inside.
                expect(l.costPerKm(since: DateTime(2026, 3, 1)), isNull);
              });

    test('does not divide by a negative span', () async {
      final l = ExpenseLedger();
      await l.initialize();
      // Odometer rolled backwards — a typo, or the base offset was changed.
      await l.add(category: ExpenseCategory.fuel, amountIdr: 50000, odometerKm: 1500);
      await l.add(category: ExpenseCategory.fuel, amountIdr: 50000, odometerKm: 1000);
      expect(l.costPerKm(), isNull);
    });
  });

  group('ExpenseLedger.monthlyBreakdown', () {
    test('groups by month, newest first', () async {
      final l = ExpenseLedger();
      await l.initialize();
      final now = DateTime.now();
      final lastMonth = DateTime(now.year, now.month - 1, 1);

      await l.add(
        category: ExpenseCategory.fuel,
        amountIdr: 50000,
        odometerKm: 100,
        at: lastMonth,
      );
      await l.add(
        category: ExpenseCategory.service,
        amountIdr: 250000,
        odometerKm: 200,
        at: DateTime(now.year, now.month, 3),
      );

      final breakdown = l.monthlyBreakdown();
      expect(breakdown.length, 2);
      expect(breakdown.first.month.month, now.month);
      expect(breakdown.first.total, 250000);
      expect(breakdown.last.month.month, lastMonth.month);
      expect(breakdown.last.total, 50000);
    });

    test('a category total across a month is correct', () async {
      final l = ExpenseLedger();
      await l.initialize();
      await l.add(
          category: ExpenseCategory.fuel,
          amountIdr: 50000,
          odometerKm: 100);
      await l.add(
          category: ExpenseCategory.fuel,
          amountIdr: 25000,
          odometerKm: 200);

      final b = l.monthlyBreakdown();
      expect(b.length, 1);
      expect(b.first.byCategory[ExpenseCategory.fuel], 75000);
      expect(b.first.total, 75000);
    });

    test('entries older than the window are excluded', () async {
      final l = ExpenseLedger();
      await l.initialize();
      await l.add(
        category: ExpenseCategory.insurance,
        amountIdr: 1200000,
        odometerKm: 100,
        at: DateTime(2019, 1, 1),
      );
      expect(l.monthlyBreakdown(), isEmpty);
      expect(l.totalIdr, 1200000,
          reason: 'still in the ledger, just outside the 12-month view');
    });
  });

  group('ExpenseLedger persistence', () {
    test('survives a reload', () async {
      final a = ExpenseLedger();
      await a.initialize();
      await a.add(
          category: ExpenseCategory.insurance,
          amountIdr: 1200000,
          odometerKm: 5000,
          note: 'Ada');

      final b = ExpenseLedger();
      await b.initialize();
      expect(b.entries.length, 1);
      expect(b.entries.first.category, ExpenseCategory.insurance);
      expect(b.entries.first.note, 'Ada');
      expect(b.totalIdr, 1200000);
    });

    test('a corrupt prefs row is skipped, not fatal', () async {
      SharedPreferences.setMockInitialValues({
        'expense_ledger_v1': '[{"id":"bad"},{"id":"good","timestamp":"2026-01-01T00:00:00.000Z","amountIdr":10.0}]'
      });
      final l = ExpenseLedger();
      await l.initialize();
      expect(l.entries.length, 1);
      expect(l.entries.first.id, 'good');
    });

    test('initialize is idempotent on a shared store', () async {
      SharedPreferences.setMockInitialValues({
        'expense_ledger_v1': '[{"id":"a","timestamp":"2026-01-01T00:00:00.000Z","amountIdr":100.0,"category":"fuel","odometerKm":10.0}]'
      });
      final l = ExpenseLedger();
      await l.initialize();
      await l.initialize();
      await l.initialize();

      // The singleton must not accumulate across reloads. Without the reset in
      // initialize() this reads 300, not 100.
      expect(l.entries.length, 1);
      expect(l.totalIdr, 100.0);
    });

    test('initialize clears state when the store is empty', () async {
      final l = ExpenseLedger();
      await l.initialize();
      await l.add(
          category: ExpenseCategory.fuel, amountIdr: 7000, odometerKm: 5);
      expect(l.totalIdr, 7000);

      // A fresh install has no stored row; the in-memory state must not leak.
      SharedPreferences.setMockInitialValues({});
      await l.initialize();
      expect(l.entries, isEmpty);
      expect(l.totalIdr, 0.0);
    });
  });
}