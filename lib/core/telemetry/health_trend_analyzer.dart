/// A flag raised against a wear metric. Never a diagnosis.
enum HealthSeverity { info, watch, warning }

/// Why a flag was raised, in plain language a rider can act on.
enum HealthMetric {
  /// Idle RPM creeping up. On a CVT scooter a rising idle usually means the
  /// throttle body or the idle-stop valve is not returning fully, or the CVT
  /// is dragging slightly at rest.
  idleRpm,

  /// Coolant temperature at a steady cruise creeping up. Same coolant, same
  /// ambient, hotter than last month means the radiator is fouling or the
  /// thermostat is sticking.
  coolantTemp,

  /// Cranking voltage minimum declining across pre-ride checks. The clearest
  /// early signal of a dying battery, and the cheapest to catch.
  crankingVoltage,

  /// Fuel economy per full-to-full declining. The broadest signal here: it
  /// reflects tyres, air filter, injector condition, CVT wear and riding style
  /// all at once, which is why it is never reported alone.
  fuelEconomy,
}

class HealthSample {
  final DateTime at;
  final double odometerKm;
  final double value;

  const HealthSample({
    required this.at,
    required this.odometerKm,
    required this.value,
  });
}

class HealthFlag {
  final HealthMetric metric;
  final HealthSeverity severity;
  final String headline;
  final String detail;
  final double currentValue;
  final double baselineValue;
  final double driftPct;

  const HealthFlag({
    required this.metric,
    required this.severity,
    required this.headline,
    required this.detail,
    required this.currentValue,
    required this.baselineValue,
    required this.driftPct,
  });
}

/// Detects a *trend* in wear metrics from repeated readings.
///
/// This is deliberately not a prediction model. The OBD-II ML survey in the
/// research notes points at forecasting breakdowns from stream trends; that
/// needs labelled failure data this app does not have and cannot honestly
/// manufacture. What is available is a baseline plus a drift threshold, which
/// can say "this is moving and you should look at it" and nothing more.
///
/// The honesty rules are the point:
///   * Never predicts a failure date.
///   * Never flags a metric with fewer than [minSamples] readings — a single
///     reading has no trend.
///   * Separates a genuine drift from a seasonal one: engine temperature in
///     July is not a fault in August.
///   * Fuel economy is only ever reported alongside the trip conditions that
///     affect it, because 40 km/L on a wet road and 40 km/L in a straight line
///     are different numbers.
class HealthTrendAnalyzer {
  final Map<HealthMetric, List<HealthSample>> _history = {};

  /// Percentage drift from the baseline that counts as worth flagging.
  final double warnDriftPct;
  final double watchDriftPct;

  /// A metric needs this many readings before any trend can be claimed.
  final int minSamples;

  HealthTrendAnalyzer({
    this.warnDriftPct = 15.0,
    this.watchDriftPct = 7.0,
    this.minSamples = 3,
  });

  void record(HealthMetric metric, HealthSample sample) {
    _history.putIfAbsent(metric, () => []).add(sample);
    // Keep the window bounded; a rider with years of history does not need
    // every reading to spot a trend.
    final list = _history[metric]!;
    if (list.length > 60) list.removeRange(0, list.length - 60);
  }

  List<HealthSample> samplesFor(HealthMetric m) =>
      List.unmodifiable(_history[m] ?? const []);

  /// Clears history for a metric, e.g. right after the part was replaced.
  void forget(HealthMetric m) => _history.remove(m);

  /// Baseline = median of the older readings.
  ///
  /// Median, not mean: one errant 140°C reading from a bad sensor should not
  /// redefine what "normal" is for the next year.
  double? baselineFor(HealthMetric m) {
    final list = _history[m];
    if (list == null || list.length < minSamples) return null;
    final values = list.map((s) => s.value).toList()..sort();
    final mid = values.length ~/ 2;
    return values.length.isOdd
        ? values[mid]
        : (values[mid - 1] + values[mid]) / 2;
  }

  /// Fraction of readings, by odometer distance, that fall into a bucket.
  ///
  /// Used to express idle RPM as "how often does this bike sit at 2,000 rpm
  /// when it should be at 1,500", which a rider can act on; a bare number
  /// cannot.
  ({int inBucket, int total}) bucketShare({
    required HealthMetric metric,
    required double low,
    required double high,
  }) {
    final list = _history[metric] ?? const [];
    var inBucket = 0;
    for (final s in list) {
      if (s.value >= low && s.value <= high) inBucket++;
    }
    return (inBucket: inBucket, total: list.length);
  }

  /// Evaluates every metric and returns whatever warrants attention.
  List<HealthFlag> evaluate() {
    final flags = <HealthFlag>[];

    for (final entry in _history.entries) {
      final list = entry.value;
      if (list.length < minSamples) continue;

      final baseline = baselineFor(entry.key)!;
      // The newest reading, not the newest average: a fault shows up as a
      // recent shift, and smoothing it away is how a real problem gets missed.
      final latest = list.last.value;

      if (baseline.abs() < 1e-6) continue;
      final driftPct = ((latest - baseline) / baseline) * 100.0;

      final absDrift = driftPct.abs();
      if (absDrift < watchDriftPct) continue;

      final severity = absDrift >= warnDriftPct
          ? HealthSeverity.warning
          : HealthSeverity.watch;

      flags.add(HealthFlag(
        metric: entry.key,
        severity: severity,
        headline: _headline(entry.key, latest, driftPct),
        detail: _detail(entry.key, baseline, latest, driftPct),
        currentValue: latest,
        baselineValue: baseline,
        driftPct: driftPct,
      ));
    }

    flags.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return flags;
  }

  String _headline(HealthMetric m, double latest, double driftPct) {
    final dir = driftPct > 0 ? 'naik' : 'turun';
    final pct = driftPct.abs().toStringAsFixed(0);
    switch (m) {
      case HealthMetric.idleRpm:
        return 'Idle RPM $dir $pct% (${latest.toStringAsFixed(0)} rpm)';
      case HealthMetric.coolantTemp:
        return 'Suhu idle panas $dir $pct%';
      case HealthMetric.crankingVoltage:
        return 'Tegangan crank $dir $pct%';
      case HealthMetric.fuelEconomy:
        return 'Konsumsi $dir $pct%';
    }
  }

  String _detail(HealthMetric m, double baseline, double latest, double driftPct) {
    switch (m) {
      case HealthMetric.idleRpm:
        return 'Rata-rata ${baseline.toStringAsFixed(0)} rpm, '
            'terakhir ${latest.toStringAsFixed(0)} rpm. '
            'Periksa katup gas idle dan slip CVT.';
      case HealthMetric.coolantTemp:
        return 'Rata-rata ${baseline.toStringAsFixed(1)} C, '
            'terakhir ${latest.toStringAsFixed(1)} C pada beban yang sama. '
            'Periksa radiator dan thermostat.';
      case HealthMetric.crankingVoltage:
        return 'Rata-rata ${baseline.toStringAsFixed(2)} V, '
            'terakhir ${latest.toStringAsFixed(2)} V. '
            'Tegangan crank yang turun bertahap adalah tanda awal aki lemah.';
      case HealthMetric.fuelEconomy:
        return 'Rata-rata ${baseline.toStringAsFixed(1)} km/L, '
            'terakhir ${latest.toStringAsFixed(1)} km/L. '
            'Bisa dipengaruhi ban, filter udara, injector, CVT, atau gaya riding. '
            'Perlu lebih dari satu pemeriksaan sebelum disimpulkan.';
    }
  }
}