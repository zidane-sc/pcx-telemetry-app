import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../garage/expense_ledger.dart';

class FuelLogEntry {
  final String id;
  final DateTime timestamp;
  final double odometerKm;
  final double liters;
  final double pricePerLiter;
  final double totalCostIdr;
  final String fuelType;
  final bool isFullTank;
  final double? calculatedKml;

  const FuelLogEntry({
    required this.id,
    required this.timestamp,
    required this.odometerKm,
    required this.liters,
    required this.pricePerLiter,
    required this.totalCostIdr,
    required this.fuelType,
    required this.isFullTank,
    this.calculatedKml,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'odometerKm': odometerKm,
        'liters': liters,
        'pricePerLiter': pricePerLiter,
        'totalCostIdr': totalCostIdr,
        'fuelType': fuelType,
        'isFullTank': isFullTank,
        'calculatedKml': calculatedKml,
      };

  factory FuelLogEntry.fromJson(Map<String, dynamic> json) => FuelLogEntry(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        odometerKm: (json['odometerKm'] as num).toDouble(),
        liters: (json['liters'] as num).toDouble(),
        pricePerLiter: (json['pricePerLiter'] as num).toDouble(),
        totalCostIdr: (json['totalCostIdr'] as num).toDouble(),
        fuelType: json['fuelType'] as String? ?? 'Pertamax 92',
        isFullTank: json['isFullTank'] as bool? ?? true,
        calculatedKml: (json['calculatedKml'] as num?)?.toDouble(),
      );
}

class FuelLogManager extends ChangeNotifier {
  static final FuelLogManager _instance = FuelLogManager._internal();
  factory FuelLogManager() => _instance;
  FuelLogManager._internal();

  final List<FuelLogEntry> _logs = [];
  List<FuelLogEntry> get logs => List.unmodifiable(_logs);

  double get totalSpentIdr => _logs.fold(0.0, (sum, e) => sum + e.totalCostIdr);
  double get totalLiters => _logs.fold(0.0, (sum, e) => sum + e.liters);

  double? get averageFullToFullKml {
    final validKmls = _logs
        .where((e) => e.calculatedKml != null && e.calculatedKml! > 10.0 && e.calculatedKml! < 80.0)
        .map((e) => e.calculatedKml!)
        .toList();

    if (validKmls.isEmpty) return null;
    return validKmls.reduce((a, b) => a + b) / validKmls.length;
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('fuel_log_history');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _logs.clear();
        for (final item in decoded) {
          _logs.add(FuelLogEntry.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (e) {
      debugPrint('[FuelLogManager] Init error: $e');
    }
    notifyListeners();
  }

  Future<void> addFillUp({
    required double odometerKm,
    required double liters,
    required double pricePerLiter,
    required String fuelType,
    required bool isFullTank,
  }) async {
    final double totalCost = liters * pricePerLiter;
    double? calculatedKml;

    // Calculate full-to-full if previous fill-up was also full tank
    if (isFullTank && _logs.isNotEmpty) {
      final lastFullIdx = _logs.indexWhere((e) => e.isFullTank);
      if (lastFullIdx >= 0) {
        final lastFull = _logs[lastFullIdx];
        final deltaOdo = odometerKm - lastFull.odometerKm;
        if (deltaOdo > 10.0 && liters > 0.5) {
          calculatedKml = deltaOdo / liters;
        }
      }
    }

    final entry = FuelLogEntry(
      id: 'fuel_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      odometerKm: odometerKm,
      liters: liters,
      pricePerLiter: pricePerLiter,
      totalCostIdr: totalCost,
      fuelType: fuelType,
      isFullTank: isFullTank,
      calculatedKml: calculatedKml,
    );

    _logs.insert(0, entry);
    await _save();
    notifyListeners();

    // A fill-up is a running-cost record, not a service event. The old code
    // pushed `odometerKm + (liters * 45.0)` as next_service_km, which is fuel
    // range dressed up as a service interval — it made every fill-up look like
    // a maintenance milestone in the timeline.
    //
    // The cost also lands in the expense ledger, so the Garage can answer
    // "what does this bike cost me" without the rider entering it twice.
    //
    // ponytail: the ledger is local-first like everything else. Wire a real
    // expense_entry collection when the Garage sync is worth the round trip.
    unawaited(ExpenseLedger().add(
      category: ExpenseCategory.fuel,
      amountIdr: totalCost,
      odometerKm: odometerKm,
      note: fuelType,
    ));
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_logs.map((e) => e.toJson()).toList());
      await prefs.setString('fuel_log_history', raw);
    } catch (_) {}
  }
}
