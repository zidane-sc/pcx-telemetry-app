import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/telemetry/health_trend_analyzer.dart';

HealthSample s(double v, {int day = 1, double odo = 1000}) =>
    HealthSample(at: DateTime(2026, 1, day), odometerKm: odo, value: v);

void main() {
  group('baseline', () {
    test('is null below the minimum sample count', () {
      final a = HealthTrendAnalyzer();
      a.record(HealthMetric.idleRpm, s(1500));
      a.record(HealthMetric.idleRpm, s(1500, day: 2));
      expect(a.baselineFor(HealthMetric.idleRpm), isNull,
          reason: 'two readings is not a trend');
      expect(a.evaluate(), isEmpty,
          reason: 'no baseline means no claim at all');
    });

    test('uses the median, not the mean', () {
      final a = HealthTrendAnalyzer();
      // A single bad sensor reading must not redefine "normal".
      a.record(HealthMetric.coolantTemp, s(80));
      a.record(HealthMetric.coolantTemp, s(82, day: 2));
      a.record(HealthMetric.coolantTemp, s(140, day: 3)); // outlier
      a.record(HealthMetric.coolantTemp, s(83, day: 4));

      expect(a.baselineFor(HealthMetric.coolantTemp), closeTo(82.5, 0.01),
          reason: 'mean would be ~96; median ignores the outlier');
    });

    test('is null for a metric never recorded', () {
      expect(HealthTrendAnalyzer().baselineFor(HealthMetric.idleRpm), isNull);
    });
  });

  group('evaluate', () {
    test('a stable metric raises nothing', () {
      final a = HealthTrendAnalyzer();
      for (var i = 0; i < 8; i++) {
        a.record(HealthMetric.idleRpm, s(1500 + (i % 2), day: i + 1));
      }
      expect(a.evaluate(), isEmpty);
    });

    test('flags a rising coolant temperature', () {
      final a = HealthTrendAnalyzer();
      for (var i = 0; i < 4; i++) {
        a.record(HealthMetric.coolantTemp, s(85, day: i + 1));
      }
      a.record(HealthMetric.coolantTemp, s(100, day: 5));
      a.record(HealthMetric.coolantTemp, s(103, day: 6));

      final flags = a.evaluate();
      expect(flags.length, 1);
      expect(flags.first.metric, HealthMetric.coolantTemp);
      expect(flags.first.severity, HealthSeverity.warning);
      expect(flags.first.driftPct, greaterThan(15));
      expect(flags.first.headline, contains('naik'));
    });

    test('flags a falling cranking voltage', () {
      final a = HealthTrendAnalyzer();
      for (var i = 0; i < 4; i++) {
        a.record(HealthMetric.crankingVoltage, s(10.6, day: i + 1));
      }
      a.record(HealthMetric.crankingVoltage, s(9.4, day: 5));

      final flags = a.evaluate();
      expect(flags.length, 1);
      expect(flags.first.metric, HealthMetric.crankingVoltage);
      expect(flags.first.driftPct, lessThan(-10),
          reason: 'a battery weakening shows as a drop, not a rise');
      expect(flags.first.detail, contains('aki'),
          reason: 'the detail must name the likely part');
    });

    test('watch and warning are distinct severities', () {
      final a = HealthTrendAnalyzer(warnDriftPct: 20, watchDriftPct: 8);
      for (var i = 0; i < 4; i++) {
        a.record(HealthMetric.idleRpm, s(1500, day: i + 1));
      }
      a.record(HealthMetric.idleRpm, s(1600, day: 5)); // ~6.7%: under watch

      expect(a.evaluate(), isEmpty);

      a.record(HealthMetric.idleRpm, s(1700, day: 6)); // ~13%: watch
      expect(a.evaluate().first.severity, HealthSeverity.watch);

      a.record(HealthMetric.idleRpm, s(1900, day: 7)); // ~27%: warning
      expect(a.evaluate().first.severity, HealthSeverity.warning);
    });

    test('sorts warnings before watches', () {
      final a = HealthTrendAnalyzer(warnDriftPct: 20, watchDriftPct: 8);
      for (var i = 0; i < 4; i++) {
        a.record(HealthMetric.coolantTemp, s(85, day: i + 1));
        a.record(HealthMetric.idleRpm, s(1500, day: i + 1));
      }
      a.record(HealthMetric.coolantTemp, s(110, day: 5)); // warning
      a.record(HealthMetric.idleRpm, s(1700, day: 5)); // watch

      final flags = a.evaluate();
      expect(flags.length, 2);
      expect(flags.first.severity, HealthSeverity.warning);
    });
  });

  group('honesty rules', () {
    test('fuel economy detail always names the confounders', () {
      final a = HealthTrendAnalyzer();
      for (var i = 0; i < 4; i++) {
        a.record(HealthMetric.fuelEconomy, s(55, day: i + 1));
      }
      a.record(HealthMetric.fuelEconomy, s(42, day: 5));

      final flag = a.evaluate().firstWhere(
          (f) => f.metric == HealthMetric.fuelEconomy);
      expect(flag.detail, contains('ban'));
      expect(flag.detail, contains('CVT'));
      expect(flag.detail, contains('gaya riding'),
          reason: 'economy is the broadest signal and must say so');
    });

    test('no flag ever predicts a failure date', () {
      final a = HealthTrendAnalyzer();
      for (var i = 0; i < 6; i++) {
        a.record(HealthMetric.crankingVoltage, s(10.5, day: i + 1));
      }
      a.record(HealthMetric.crankingVoltage, s(8.0, day: 7));

      for (final f in a.evaluate()) {
        expect(f.headline, isNot(contains('hari')));
        expect(f.headline, isNot(contains('minggu')));
        expect(f.detail, isNot(contains('akan rusak')));
        expect(f.detail, isNot(contains('akan mati')));
      }
    });

    test('every flag names a part to check, never a verdict', () {
      final a = HealthTrendAnalyzer();
      for (var i = 0; i < 4; i++) {
        a.record(HealthMetric.coolantTemp, s(85, day: i + 1));
      }
      a.record(HealthMetric.coolantTemp, s(110, day: 5));

      final f = a.evaluate().first;
      expect(f.detail, anyOf(contains('Periksa'), contains('periksa')));
    });

    test('a zero baseline does not produce an infinite drift', () {
      final a = HealthTrendAnalyzer();
      for (var i = 0; i < 4; i++) {
        a.record(HealthMetric.idleRpm, s(0, day: i + 1));
      }
      a.record(HealthMetric.idleRpm, s(1500, day: 5));
      expect(a.evaluate(), isEmpty,
          reason: 'division by a zero baseline must not produce a flag');
    });
  });

  group('housekeeping', () {
    test('forget clears a metric', () {
      final a = HealthTrendAnalyzer();
      for (var i = 0; i < 4; i++) {
        a.record(HealthMetric.crankingVoltage, s(10.5, day: i + 1));
      }
      a.record(HealthMetric.crankingVoltage, s(9.0, day: 5));
      expect(a.evaluate(), isNotEmpty);

      a.forget(HealthMetric.crankingVoltage);
      expect(a.evaluate(), isEmpty,
          reason: 'right after a battery replacement the old trend is noise');
    });

    test('the history window is bounded', () {
      final a = HealthTrendAnalyzer();
      for (var i = 0; i < 200; i++) {
        a.record(HealthMetric.idleRpm, s(1500 + (i % 5), day: (i % 28) + 1));
      }
      expect(a.samplesFor(HealthMetric.idleRpm).length, lessThanOrEqualTo(60));
    });

    test('bucketShare counts a range', () {
      final a = HealthTrendAnalyzer();
      for (final v in [1500.0, 1550.0, 2000.0, 1450.0]) {
        a.record(HealthMetric.idleRpm, s(v));
      }
      final share = a.bucketShare(
          metric: HealthMetric.idleRpm, low: 1400, high: 1600);
      expect(share.total, 4);
      expect(share.inBucket, 3);
    });
  });
}