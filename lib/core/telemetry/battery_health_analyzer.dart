enum BatteryCondition { healthy, warning, replace }

class BatteryHealthResult {
  final double standbyVoltage;
  final double crankingMinVoltage;
  final BatteryCondition condition;
  final String diagnosis;

  const BatteryHealthResult({
    required this.standbyVoltage,
    required this.crankingMinVoltage,
    required this.condition,
    required this.diagnosis,
  });
}

class BatteryHealthAnalyzer {
  double? _lowestCrankingVoltage;
  bool _isCranking = false;

  void onEngineStartInitiated() {
    _isCranking = true;
    _lowestCrankingVoltage = null;
  }

  void recordVoltageSample(double volt) {
    if (_isCranking) {
      if (_lowestCrankingVoltage == null || volt < _lowestCrankingVoltage!) {
        _lowestCrankingVoltage = volt;
      }
    }
  }

  BatteryHealthResult evaluate({required double standbyVolt}) {
    _isCranking = false;
    final double minVolt = _lowestCrankingVoltage ?? standbyVolt;

    BatteryCondition condition;
    String diagnosis;

    if (minVolt >= 10.0) {
      condition = BatteryCondition.healthy;
      diagnosis = 'Aki Prima! Cranking drop normal (${minVolt.toStringAsFixed(1)}V).';
    } else if (minVolt >= 9.5) {
      condition = BatteryCondition.warning;
      diagnosis =
          'Performa Aki Menurun (${minVolt.toStringAsFixed(1)}V). Pertimbangkan cek charging kiprok/cas aki.';
    } else {
      condition = BatteryCondition.replace;
      diagnosis =
          'Aki Soak Kritis (${minVolt.toStringAsFixed(1)}V)! Risiko mogok mendadak saat starter dingin.';
    }

    return BatteryHealthResult(
      standbyVoltage: standbyVolt,
      crankingMinVoltage: minVolt,
      condition: condition,
      diagnosis: diagnosis,
    );
  }
}
