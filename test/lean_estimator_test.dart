import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/telemetry/lean_estimator.dart';

/// Three consecutive GPS fixes on a circle of known radius, projected back to
/// lat/lon around a reference point so the estimator's equirectangular
/// approximation can be checked against exact geometry.
class ArcPoints {
  final double lat1, lon1, lat2, lon2, lat3, lon3;

  ArcPoints(this.lat1, this.lon1, this.lat2, this.lon2, this.lat3, this.lon3);

  factory ArcPoints.circle({
    required double centerLat,
    required double centerLon,
    required double radiusM,
    double startDeg = 90.0,
    double stepDeg = 4.0,
  }) {
    double mPerDegLat = pi * 6371008.8 / 180.0;
    double mPerDegLon = mPerDegLat * cos(centerLat * pi / 180.0);

    (double lat, double lon) at(double deg) {
      final r = deg * pi / 180.0;
      return (
        centerLat + (radiusM * sin(r)) / mPerDegLat,
        centerLon + (radiusM * cos(r)) / mPerDegLon
      );
    }

    final p1 = at(startDeg);
    final p2 = at(startDeg + stepDeg);
    final p3 = at(startDeg + 2 * stepDeg);
    return ArcPoints(p1.$1, p1.$2, p2.$1, p2.$2, p3.$1, p3.$2);
  }
}

void main() {
  group('LeanEstimator.gpsLeanDeg — physics', () {
    test('45 degrees of lean is exactly 1.0 g of cornering force', () {
      // tan(45°) = 1, so v²/(g·r) = 1 → r = v²/g.
      final speed = 60.0; // km/h
      final v = speed / 3.6;
      final radius = (v * v) / LeanEstimator.g;

      final lean = LeanEstimator.gpsLeanDeg(speedKmh: speed, radiusM: radius);
      expect(lean, closeTo(45.0, 0.01));
      expect(
        LeanEstimator.lateralG(speedKmh: speed, radiusM: radius),
        closeTo(1.0, 0.001),
      );
    });

    test('straight line (infinite radius) yields zero lean', () {
      final lean = LeanEstimator.gpsLeanDeg(speedKmh: 80.0, radiusM: 1e12);
      expect(lean, closeTo(0.0, 0.001));
    });

    test('the same speed in a tighter corner yields more lean', () {
      // Computed from v²/(g·r), not recalled:
      //   60 km/h, r=200 m → 8.06°   (0.14 g, a fast sweeper)
      //   60 km/h, r= 30 m → 43.35°  (0.94 g, a hairpin)
      final sweeper = LeanEstimator.gpsLeanDeg(speedKmh: 60.0, radiusM: 200.0)!;
      final hairpin = LeanEstimator.gpsLeanDeg(speedKmh: 60.0, radiusM: 30.0)!;
      expect(hairpin, greaterThan(sweeper));
      expect(sweeper, closeTo(8.06, 0.1));
      expect(hairpin, closeTo(43.35, 0.1));
    });

    test('a gentle turn at low speed gives a small angle', () {
      // 20 km/h, r=500 m → 0.36°
      final lean = LeanEstimator.gpsLeanDeg(speedKmh: 20.0, radiusM: 500.0)!;
      expect(lean, closeTo(0.36, 0.05));
    });

    test('returns null below the minimum speed', () {
      expect(
        LeanEstimator.gpsLeanDeg(speedKmh: 7.9, radiusM: 100.0),
        isNull,
        reason: 'GPS radius is meaningless at walking pace',
      );
      expect(LeanEstimator.gpsLeanDeg(speedKmh: 8.0, radiusM: 100.0), isNotNull);
    });

    test('returns null for a non-positive or unknown radius', () {
      expect(LeanEstimator.gpsLeanDeg(speedKmh: 50.0, radiusM: 0.0), isNull);
      expect(LeanEstimator.gpsLeanDeg(speedKmh: 50.0, radiusM: -20.0), isNull);
      expect(LeanEstimator.gpsLeanDeg(speedKmh: 50.0, radiusM: double.nan),
          isNull);
    });

    test('never exceeds a physically sane bound', () {
      // Absurd radius: should clamp, not produce nonsense.
      final lean = LeanEstimator.gpsLeanDeg(speedKmh: 200.0, radiusM: 0.5)!;
      expect(lean, lessThanOrEqualTo(85.0));
    });
  });

  group('LeanEstimator.radiusFromFixes — geometry', () {
    test('recovers the true radius of a circular arc', () {
      const trueRadius = 120.0;
      final pts = ArcPoints.circle(
        centerLat: -6.2,
        centerLon: 106.8,
        radiusM: trueRadius,
      );

      final r = LeanEstimator.radiusFromFixes(
        lat1: pts.lat1,
        lon1: pts.lon1,
        lat2: pts.lat2,
        lon2: pts.lon2,
        lat3: pts.lat3,
        lon3: pts.lon3,
      );

      expect(r, isNotNull);
      expect(r!, closeTo(trueRadius, 1.0),
          reason: 'equirectangular projection should be near-exact over 120 m');
    });

    test('recovers a tight hairpin radius too', () {
      const trueRadius = 25.0;
      final pts = ArcPoints.circle(
        centerLat: -6.2,
        centerLon: 106.8,
        radiusM: trueRadius,
        stepDeg: 8.0,
      );
      final r = LeanEstimator.radiusFromFixes(
        lat1: pts.lat1,
        lon1: pts.lon1,
        lat2: pts.lat2,
        lon2: pts.lon2,
        lat3: pts.lat3,
        lon3: pts.lon3,
      );
      expect(r, isNotNull);
      expect(r!, closeTo(trueRadius, 0.8));
    });

    test('rejects three collinear fixes (a straight road)', () {
      // Three points due north on the same longitude: a perfectly straight line.
      final r = LeanEstimator.radiusFromFixes(
        lat1: -6.200,
        lon1: 106.800,
        lat2: -6.201,
        lon2: 106.800,
        lat3: -6.202,
        lon3: 106.800,
      );
      expect(r, isNull,
          reason: 'a straight road must not fabricate a corner');
    });

    test('rejects fixes too close together to form an arc', () {
      // Three fixes within a couple of metres: multipath jitter, not geometry.
      final r = LeanEstimator.radiusFromFixes(
        lat1: -6.200000,
        lon1: 106.800000,
        lat2: -6.200005,
        lon2: 106.800003,
        lat3: -6.200010,
        lon3: 106.800001,
      );
      expect(r, isNull);
    });

    test('rejects a degenerate duplicate-point triangle', () {
      final r = LeanEstimator.radiusFromFixes(
        lat1: -6.2,
        lon1: 106.8,
        lat2: -6.2,
        lon2: 106.8,
        lat3: -6.2,
        lon3: 106.8,
      );
      expect(r, isNull);
    });

    test('a wide-radius arc is still detected, not rejected as straight', () {
      // 2 km radius sweeping 8 degrees: a real, gentle curve.
      final pts = ArcPoints.circle(
        centerLat: -6.2,
        centerLon: 106.8,
        radiusM: 2000.0,
        stepDeg: 1.0,
      );
      final r = LeanEstimator.radiusFromFixes(
        lat1: pts.lat1,
        lon1: pts.lon1,
        lat2: pts.lat2,
        lon2: pts.lon2,
        lat3: pts.lat3,
        lon3: pts.lon3,
      );
      expect(r, isNotNull);
      expect(r!, closeTo(2000.0, 20.0));
    });
  });

  group('LeanEstimator.fromSources — provenance and camber', () {
    test('dualSource when both agree', () {
      // 60 km/h in a 105.7 m radius is 15.0° of lean (0.26 g). Feeding the
      // IMU that same figure means the two sources agree.
      const radius = 105.676;
      final gpsDeg =
          LeanEstimator.gpsLeanDeg(speedKmh: 60.0, radiusM: radius)!;
      expect(gpsDeg, closeTo(15.0, 0.1));

      final r = LeanEstimator.fromSources(
        imuDeg: gpsDeg,
        speedKmh: 60.0,
        radiusM: radius,
      );
      expect(r.confidence, LeanConfidence.dualSource);
      expect(r.gpsDeg, isNotNull);
      expect(r.camberDeg!.abs(), lessThan(
        LeanEstimator.divergenceToleranceDeg,
      ));
      expect(r.camberDeg!.abs(), closeTo(0.0, 0.01));
    });

    test('imuOnly when radius is unknown', () {
      final r = LeanEstimator.fromSources(
        imuDeg: 35.0,
        speedKmh: 60.0,
        radiusM: null,
      );
      expect(r.confidence, LeanConfidence.imuOnly);
      expect(r.gpsDeg, isNull);
      expect(r.camberDeg, isNull,
          reason: 'camber is the residual; without a GPS figure there is none');
    });

    test('imuOnly below the minimum GPS speed', () {
      final r = LeanEstimator.fromSources(
        imuDeg: 12.0,
        speedKmh: 5.0,
        radiusM: 30.0,
      );
      expect(r.confidence, LeanConfidence.imuOnly);
    });

    test('degraded when the two sources diverge beyond tolerance', () {
      // 40 degrees of lean in a 100 m radius at 60 km/h is physically
      // impossible (that geometry yields ~15 degrees). A loose mount or a
      // cambered road produces exactly this, and the reading must be flagged
      // rather than trusted.
      final r = LeanEstimator.fromSources(
        imuDeg: 40.0,
        speedKmh: 60.0,
        radiusM: 100.0,
      );
      expect(r.confidence, LeanConfidence.degraded);
      expect(r.gpsDeg, isNotNull);
      expect(r.camberDeg!.abs(),
          greaterThan(LeanEstimator.divergenceToleranceDeg));
    });

    test('camber residual points the right way on a banked road', () {
      // Road crown tilted so the IMU over-reads by 6 degrees: the residual
      // must be positive (IMU minus GPS), naming the camber as the cause.
      // 24.8° of true lean at 60 km/h comes from r = 61.3 m.
      const radius = 61.281;
      final trueLean =
          LeanEstimator.gpsLeanDeg(speedKmh: 60.0, radiusM: radius)!;
      expect(trueLean, closeTo(24.8, 0.1));

      final r = LeanEstimator.fromSources(
        imuDeg: trueLean + 6.0,
        speedKmh: 60.0,
        radiusM: radius,
      );
      expect(r.camberDeg, closeTo(6.0, 0.1));
    });

    test('an upright bike on a cambered road reports camber, not lean', () {
      // Physically the rider is vertical, so the GPS geometry says ~0. The IMU,
      // referenced to gravity, reads the road tilt. This is the exact trap the
      // feature exists to expose.
      final r = LeanEstimator.fromSources(
        imuDeg: 6.0,
        speedKmh: 60.0,
        radiusM: 1e12,
      );
      expect(r.gpsDeg, closeTo(0.0, 0.01));
      expect(r.camberDeg, closeTo(6.0, 0.01));
    });

    test('GPS sign follows the IMU direction', () {
      final left = LeanEstimator.fromSources(
        imuDeg: -30.0,
        speedKmh: 60.0,
        radiusM: 100.0,
      );
      final right = LeanEstimator.fromSources(
        imuDeg: 30.0,
        speedKmh: 60.0,
        radiusM: 100.0,
      );
      expect(left.gpsDeg, isNotNull);
      expect(left.gpsDeg, lessThan(0));
      expect(right.gpsDeg, greaterThan(0));
      expect(left.gpsDeg!.abs(), closeTo(right.gpsDeg!.abs(), 0.001));
    });

    test('displayDeg is always the IMU figure', () {
      final r = LeanEstimator.fromSources(
        imuDeg: 33.0,
        speedKmh: 60.0,
        radiusM: 100.0,
      );
      expect(r.displayDeg, 33.0);
    });
  });
}