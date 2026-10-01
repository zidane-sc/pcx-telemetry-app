import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a spend was for. Deliberately coarse: a rider will not categorise a
/// 12,950 rupiah fuel stop any more precisely than "fuel", and a category tree
/// they have to think about is one they will stop using.
enum ExpenseCategory {
  fuel('Bensin', 0xFF00FF66),
  service('Servis', 0xFF00E5FF),
  parts('Sparepart', 0xFFFFB300),
  tires('Ban', 0xFFFF5252),
  insurance('Asuransi', 0xFF7C4DFF),
  tax('Pajak & STNK', 0xFF9E9E9E),
  accessory('Aksesori', 0xFF00BCD4),
  other('Lainnya', 0xFF78909C);

  const ExpenseCategory(this.label, this.colorValue);
  final String label;
  final int colorValue;

  static ExpenseCategory fromName(String? name) {
    for (final c in ExpenseCategory.values) {
      if (c.name == name) return c;
    }
    return ExpenseCategory.other;
  }
}

class ExpenseEntry {
  final String id;
  final DateTime timestamp;
  final ExpenseCategory category;
  final double amountIdr;

  /// Odometer at the time of the spend. Used for per-km cost.
  final double odometerKm;

  /// Free-text note: which shop, which part.
  final String note;

  const ExpenseEntry({
    required this.id,
    required this.timestamp,
    required this.category,
    required this.amountIdr,
    required this.odometerKm,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'category': category.name,
        'amountIdr': amountIdr,
        'odometerKm': odometerKm,
        'note': note,
      };

  /// Returns null rather than throwing. One corrupt row must not cost the
  /// rider the rest of their expense history.
  static ExpenseEntry? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final ts = json['timestamp'];
    final amt = json['amountIdr'];
    if (id is! String || ts is! String || amt is! num) return null;
    return ExpenseEntry(
      id: id,
      timestamp: DateTime.tryParse(ts) ?? DateTime.fromMillisecondsSinceEpoch(0),
      category: ExpenseCategory.fromName(json['category'] as String?),
      amountIdr: amt.toDouble(),
      odometerKm: (json['odometerKm'] is num)
          ? (json['odometerKm'] as num).toDouble()
          : 0.0,
      note: json['note'] as String? ?? '',
    );
  }
}

/// A monthly rollup.
class MonthlyExpense {
  final DateTime month; // first day of the month
  final Map<ExpenseCategory, double> byCategory;
  final double total;

  const MonthlyExpense({
    required this.month,
    required this.byCategory,
    required this.total,
  });
}

/// Running cost-of-ownership ledger.
///
/// Separate from [FuelLogManager] on purpose: fuel is tracked there by
/// fill-up because it needs full-to-full accounting for economy, and mixing the
/// two would put an oil change and a fuel stop in the same list. This ledger
/// answers "what does this bike cost me", which the fuel log cannot.
///
/// `ponytail:` no cloud sync yet. The data is local-first like everything else
/// in this app; add a PocketBase sync when there is a collection to put it in,
/// rather than shipping a half-wired outbox now.
class ExpenseLedger extends ChangeNotifier {
  static final ExpenseLedger _instance = ExpenseLedger._internal();
  factory ExpenseLedger() => _instance;
  ExpenseLedger._internal();

  static const String _prefsKey = 'expense_ledger_v1';

  final List<ExpenseEntry> _entries = [];
  List<ExpenseEntry> get entries => List.unmodifiable(_entries);

  Future<void> initialize() async {
    // Reset first, always. This is a singleton, so a second initialize() — or a
    // test that calls it between cases — would otherwise inherit the previous
    // state and silently double-count every total.
    _entries.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        notifyListeners();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        notifyListeners();
        return;
      }
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final e = ExpenseEntry.fromJson(item);
        if (e != null) _entries.add(e);
      }
    } catch (e) {
      debugPrint('[ExpenseLedger] init failed: $e');
    }
    notifyListeners();
  }

  Future<ExpenseEntry> add({
    required ExpenseCategory category,
    required double amountIdr,
    required double odometerKm,
    String note = '',
    DateTime? at,
  }) async {
    final entry = ExpenseEntry(
      id: 'exp_${DateTime.now().microsecondsSinceEpoch}',
      timestamp: at ?? DateTime.now(),
      category: category,
      amountIdr: amountIdr,
      odometerKm: odometerKm,
      note: note,
    );
    _entries.insert(0, entry);
    await _save();
    notifyListeners();
    return entry;
  }

  Future<void> remove(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _save();
    notifyListeners();
  }

  double get totalIdr =>
      _entries.fold(0.0, (sum, e) => sum + e.amountIdr);

  double totalFor(ExpenseCategory c) =>
      _entries.where((e) => e.category == c).fold(0.0, (s, e) => s + e.amountIdr);

  /// Cost per kilometre over a window.
  ///
  /// Uses odometer *delta*, not distance travelled since inception: the rider's
  /// first expense is not at zero km, and dividing by the odometer reading would
  /// understate the cost for a bike that already has 12,000 km on it.
  ///
  /// Returns null when there is not enough history to be honest about it —
  /// two entries 3 km apart say nothing about running costs.
  double? costPerKm({
    DateTime? since,
    int minEntries = 2,
    double minDistanceKm = 50.0,
  }) {
    final list = since == null
        ? [..._entries]
        : _entries.where((e) => e.timestamp.isAfter(since)).toList();
    if (list.length < minEntries) return null;

    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final span = list.last.odometerKm - list.first.odometerKm;
    if (span < minDistanceKm) return null;

    final spend = list.fold(0.0, (s, e) => s + e.amountIdr);
    return spend / span;
  }

  /// Monthly rollups, newest first.
  List<MonthlyExpense> monthlyBreakdown({int months = 12}) {
    final buckets = <DateTime, Map<ExpenseCategory, double>>{};
    final cutoff = DateTime(
        DateTime.now().year, DateTime.now().month - (months - 1), 1);

    for (final e in _entries) {
      if (e.timestamp.isBefore(cutoff)) continue;
      final key = DateTime(e.timestamp.year, e.timestamp.month, 1);
      final bucket = buckets.putIfAbsent(key, () => <ExpenseCategory, double>{});
      bucket[e.category] = (bucket[e.category] ?? 0.0) + e.amountIdr;
    }

    final keys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.map((k) {
      final byCat = buckets[k]!;
      return MonthlyExpense(
        month: k,
        byCategory: byCat,
        total: byCat.values.fold(0.0, (s, v) => s + v),
      );
    }).toList();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}