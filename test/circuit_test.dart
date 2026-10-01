import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/trip/circuit.dart';

/// Builds a point `metersM` east of a reference, at Jakarta's latitude so the
/// longitude-degree scaling is realistic.
LatLngPoint eastOf(double lat, double lng, double meters) {
  final mPerDegLon = 111320 * math.cos(lat * math.pi / 180.0);
  return LatLngPoint(lat, lng + meters / mPerDegLon);
}

void main() {
  // A reference point in Jakarta, with a gate that is 40 m wide.
    const lat = -6.2, lng = 106.8;
    final gate = eastOf(lat, lng, 0);
  final circuit = Circuit(
    id: 'sunmori',
    name: 'Sunmori',
    startLat: gate.lat,
    startLng: gate.lng,
    startRadiusM: 40.0,
    points: const [],
    lengthM: 2000.0,
  );

  DateTime t = DateTime(2026, 1, 1, 12);

  /// Feeds a path of (meters east of the gate, cumulative seconds).
  ///
  /// Timestamps are ABSOLUTE within a path, not deltas: each entry says "at
  /// this many seconds from the start of this leg", so `t` advances to that
  /// point. Treating them as deltas made every lap duration the sum of all
  /// ticks rather than the span from first to last, which is not a duration.
  LapResult? feed(
    LapCounter c,
    List<(double metersEast, double sec)> path, {
    double speedKmh = 60.0,
  }) {
    final base = t;
    LapResult? done;
    for (final (m, s) in path) {
      final at = base.add(Duration(milliseconds: (s * 1000).round()));
      t = at;
      final r = c.update(
        now: at,
        lat: lat,
        lng: gate.lng + m / (111320 * math.cos(lat * math.pi / 180.0)),
        speedKmh: speedKmh,
      );
      if (r != null) done = r;
    }
    return done;
  }

  group('haversineM', () {
    test('is zero for the same point', () {
      expect(haversineM(lat, lng, lat, lng), closeTo(0.0, 0.001));
    });

    test('matches a known distance', () {
      final d = haversineM(lat, lng, lat, lng + 0.01);
      expect(d, greaterThan(1000));
      expect(d, lessThan(1200));
    });
  });

  group('circuitFromTrip', () {
    test('places the start line at the first fix', () {
      final c = circuitFromTrip(
        id: 'x',
        name: 'X',
        fixPoints: const [LatLngPoint(-6.2, 106.8), LatLngPoint(-6.3, 106.9)],
      );
      expect(c.startLat, -6.2);
      expect(c.startLng, 106.8);
    });

    test('computes the total length', () {
      final pts = [const LatLngPoint(-6.2, 106.8), eastOf(-6.2, 106.8, 1000)];
      final c = circuitFromTrip(id: 'x', name: 'X', fixPoints: pts);
      expect(c.lengthM, closeTo(1000, 5));
    });

    test('rejects a fix list too short to be a route', () {
      expect(
        () => circuitFromTrip(
            id: 'x', name: 'X', fixPoints: const [LatLngPoint(-6.2, 106.8)]),
        throwsArgumentError,
      );
      expect(
        () => circuitFromTrip(id: 'x', name: 'X', fixPoints: const []),
        throwsArgumentError,
      );
    });
  });

  group('LapCounter — must not count', () {
    test('standing still at the gate does not start a lap', () {
      t = DateTime(2026, 1, 1, 12);
      final c = LapCounter(circuit);
      // Five fixes all inside the gate.
      feed(c, [(0, 0), (5, 1), (10, 1), (15, 1), (20, 1)]);
      expect(c.laps, isEmpty);
      expect(c.state, LapState.standing,
          reason: 'the rider has not left yet');
    });

    test('GPS jitter at the gate does not close a lap', () {
      t = DateTime(2026, 1, 1, 12);
      final c = LapCounter(circuit);
      // Depart, then bounce around inside the gate for a second.
      feed(c, [(0, 0), (60, 1), (200, 1)]);
      for (var i = 0; i < 6; i++) {
        feed(c, [(0 + (i % 3) * 2, 0.2)]);
      }
      expect(c.laps, isEmpty,
          reason: 'crossings inside the debounce window are one crossing');
    });

    test('a teleport jump does not inflate lap distance', () {
      t = DateTime(2026, 1, 1, 12);
      final c = LapCounter(circuit);
      // Legitimate outbound leg over 20 s, out to 600 m.
      feed(c, [(0, 0), (200, 5), (400, 10), (600, 15)]);
      // 5 km in one second is not a motorcycle; the step must be rejected.
      feed(c, [(5600, 16)]);
      // Come back legitimately.
      feed(c, [(300, 20), (100, 25), (0, 30)]);

      expect(c.laps.length, 1);
      // Without rejection the lap would be ~10.2 km. With it, ~1.2 km.
      expect(c.laps.first.distanceM, lessThan(2000),
          reason: 'a rejected jump must not be counted as distance');
      expect(c.laps.first.distanceM, greaterThan(LapCounter.minLapDistanceM));
    });
  });

  group('LapCounter — must count', () {
    test('a depart-and-return closes one lap', () {
      t = DateTime(2026, 1, 1, 12);
      final c = LapCounter(circuit);
      // Out to 600 m over 20 s, back to the gate. Comfortably clear of the
      // 15 s minimum and the 200 m minimum, so this is unambiguously a lap.
      final lap = feed(c, [
        (0, 0), // arm at gate
        (60, 4), (200, 8), (400, 12), (600, 16), // outbound
        (500, 18), (300, 20), (100, 22), (0, 24), // inbound
      ]);
      expect(lap, isNotNull);
      expect(c.laps.length, 1);
      expect(c.laps.first.lapNumber, 1);
      expect(c.laps.first.duration.inSeconds, 24);
      expect(c.laps.first.distanceM, greaterThan(LapCounter.minLapDistanceM));
    });

    test('a return inside the minimum lap time is not a lap', () {
      t = DateTime(2026, 1, 1, 12);
      final c = LapCounter(circuit);
      // 600 m round trip in 8 s: a real return, but far too fast to be a lap.
      final lap = feed(c, [
        (0, 0), (300, 4), (600, 6), (300, 7), (0, 8),
      ]);
      expect(lap, isNull);
      expect(c.laps, isEmpty);
    });

    test('a return with too little distance is not a lap', () {
      t = DateTime(2026, 1, 1, 12);
      final c = LapCounter(circuit);
      // 30 s (past the time floor) but only 100 m: pausing just past the line.
      final lap = feed(c, [
        (0, 0), (30, 10), (60, 20), (100, 30), (0, 35),
      ]);
      expect(lap, isNull);
      expect(c.laps, isEmpty);
    });

    test('two full laps produce two results', () {
      t = DateTime(2026, 1, 1, 12);
      final c = LapCounter(circuit);
      // First lap: 20 s, 600 m out and back.
      feed(c, [
        (0, 0), (300, 5), (600, 10), (300, 15), (0, 20),
      ]);
      expect(c.laps.length, 1);

      // Second lap: 18 s.
      feed(c, [
        (300, 4), (600, 9), (300, 13), (0, 18),
      ]);
      expect(c.laps.length, 2);
      expect(c.laps.last.lapNumber, 2);
      expect(c.laps.last.duration.inSeconds, 18);
    });

    test('a faster lap is reported as best', () {
      t = DateTime(2026, 1, 1, 12);
      final c = LapCounter(circuit);
      // Slow lap: 40 s.
      feed(c, [
        (0, 0), (300, 10), (600, 20), (300, 30), (0, 40),
      ]);
      // Fast lap: 20 s, still clear of both minimums.
      feed(c, [
        (300, 5), (600, 10), (300, 15), (0, 20),
      ]);
      expect(c.laps.length, 2);
      expect(c.bestLap!.lapNumber, 2);
      expect(c.bestLap!.duration.inSeconds, 20);
    });

    test('average speed is derived from distance and time', () {
      t = DateTime(2026, 1, 1, 12);
      final c = LapCounter(circuit);
      // 600 m out and 600 m back in 20 s. Absurd for this bike, but the point
      // is that the arithmetic must not produce NaN, infinity, or a negative.
      final lap = feed(c, [
        (0, 0), (300, 5), (600, 10), (300, 15), (0, 20),
      ])!;
      expect(lap.distanceM, closeTo(1200, 30));
      expect(lap.avgSpeedKmh.isFinite, isTrue);
      expect(lap.avgSpeedKmh, closeTo(lap.distanceM / 1000 / (20 / 3600), 1.0));
    });

    test('reset clears laps but keeps the circuit', () {
      t = DateTime(2026, 1, 1, 12);
      final c = LapCounter(circuit);
      feed(c, [
        (0, 0), (300, 10), (600, 20), (300, 30), (0, 40),
      ]);
      expect(c.laps.length, 1);
      c.reset();
      expect(c.laps, isEmpty);
      expect(c.circuit.id, 'sunmori');
    });
  });

  group('splitIntoSectors', () {
    test('returns empty for too few samples', () {
      expect(splitIntoSectors(const <LapSample>[]), isEmpty);
      expect(
        splitIntoSectors([
          LapSample(
              const Duration(seconds: 1), const LatLngPoint(-6.2, 106.8), 50.0),
        ]),
        isEmpty,
      );
    });

    test('splits a lap into the requested number of sectors', () {
      // 12 samples, 1 second apart = 12 s lap, split into 3.
      final samples = <LapSample>[];
      for (var i = 0; i < 12; i++) {
        samples.add(LapSample(
          Duration(seconds: i),
          eastOf(-6.2, 106.8, i * 100.0),
          60.0,
        ));
      }
      final sectors = splitIntoSectors(samples, sectorCount: 3);
      expect(sectors.length, 3);
      // The sectors must sum to the lap.
      final total = sectors.fold<int>(0, (s, x) => s + x.time.inMilliseconds);
      expect(total, 11000,
          reason: 'sector times reconstruct the lap, minus the first sample');
    });

    test('sector boundaries land near the time fractions', () {
      final samples = <LapSample>[];
      for (var i = 0; i < 12; i++) {
        samples.add(LapSample(
          Duration(seconds: i),
          eastOf(-6.2, 106.8, i * 100.0),
          60.0,
        ));
      }
      final sectors = splitIntoSectors(samples, sectorCount: 3);
      // Each sector should be about 11/3 = 3.67 s.
      for (final s in sectors) {
        expect(s.time.inMilliseconds, inInclusiveRange(3000, 4200));
      }
    });
  });
}