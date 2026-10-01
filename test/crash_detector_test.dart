import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/telemetry/crash_detector.dart';

void main() {
  DateTime t0 = DateTime(2026, 1, 1, 12);

  /// Drives a sequence of (elapsedMs, netG, speed) samples.
  List<CrashDetection> run(
    CrashDetector d,
    List<(int, double, double)> samples, {
    bool isBike = true,
    bool armed = true,
  }) {
    final out = <CrashDetection>[];
    for (final (ms, g, spd) in samples) {
      out.add(d.update(
        now: t0.add(Duration(milliseconds: ms)),
        netG: g,
        speedKmh: spd,
        isBike: isBike,
        armed: armed,
      ));
    }
    return out;
  }

  CrashDetector armed() {
    final d = CrashDetector();
    // Arm well past the grace period so the guard is not what is under test.
    d.arm(now: t0.subtract(const Duration(seconds: 30)));
    return d;
  }

  group('CrashDetector — must not fire', () {
    test('a pothole does not trigger it', () {
      final d = armed();
      // 1.6 g spike over 200 ms, then back to normal. No free-fall phase.
      final r = run(d, [
        (0, 0.0, 45.0),
        (100, 1.6, 45.0),
        (200, 1.7, 45.0),
        (300, 0.0, 45.0),
        (400, 0.0, 45.0),
      ]);
      expect(r.every((s) => s.state == CrashState.normal), isTrue,
          reason: 'a pothole spikes G high but never drops it to zero');
    });

    test('a violent pothole at speed does not trigger it', () {
      final d = armed();
      final r = run(d, [
        (0, 0.0, 80.0),
        (60, 2.2, 80.0),
        (120, 2.4, 80.0),
        (180, 0.1, 80.0),
        (240, 0.0, 80.0),
      ]);
      expect(r.last.state, CrashState.normal);
    });

    test('engine vibration never triggers it', () {
      final d = armed();
      final r = <CrashDetection>[];
      for (var i = 0; i < 200; i++) {
        // 100 Hz vibration with a large vertical component.
        final g = 0.35 * math_sin(i.toDouble());
        r.add(d.update(
          now: t0.add(Duration(milliseconds: i * 10)),
          netG: g,
          speedKmh: 50.0,
          isBike: true,
        ));
      }
      expect(r.every((s) => s.state == CrashState.normal), isTrue);
    });

    test('a high-G event without free-fall first is ignored', () {
      final d = armed();
      // Some phones report a large positive G on a hard stop with no preceding
      // free-fall. That is not a crash.
      final r = run(d, [
        (0, 0.0, 50.0),
        (100, 4.5, 50.0),
        (200, 4.0, 50.0),
        (300, 0.0, 50.0),
      ]);
      expect(r.every((s) => s.state == CrashState.normal), isTrue,
          reason: 'high-G without a free-fall phase is a pothole or a stop');
    });

    test('a parked knock-over does not trigger it', () {
      final d = armed();
      final r = run(d, [
        (0, 0.0, 0.0),
        (100, -0.9, 0.0), // phone tips off the seat
        (200, 3.8, 0.0), // hits the ground
        (300, 0.0, 0.0),
      ]);
      expect(r.every((s) => s.state == CrashState.normal), isTrue,
          reason: 'below minImpactSpeedKmh there is no crash');
    });

    test('free-fall alone, with no impact, resets rather than latching', () {
      final d = armed();
      final r = run(d, [
        (0, 0.0, 50.0),
        (100, -0.8, 50.0),
        (200, -0.8, 50.0),
        (300, 0.0, 50.0), // caught in a pocket
        (400, 0.0, 50.0),
        (500, 0.0, 50.0),
      ]);
      expect(r.last.state, CrashState.normal,
          reason: 'the rider pocketed the phone; that is not a crash');
      expect(d.state, CrashState.normal);
    });

    test('the car profile never triggers it', () {
      final d = armed();
      final r = run(d, [
        (0, 0.0, 90.0),
        (100, -0.9, 90.0),
        (250, 5.0, 90.0),
      ], isBike: false);
      expect(r.every((s) => s.state == CrashState.normal), isTrue,
          reason: 'car crash dynamics are out of scope; do not claim them');
    });

    test('shaking before the grace period expires is ignored', () {
      final d = CrashDetector();
      d.arm(now: t0); // grace period starts now
      final r = run(d, [
        (0, -0.9, 50.0),
        (150, 4.5, 50.0),
      ]);
      expect(r.every((s) => s.state == CrashState.normal), isTrue,
          reason: 'moving the bike with the phone on the seat is not a crash');
    });
  });

  group('CrashDetector — must fire', () {
    test('free-fall then impact at speed triggers the countdown', () {
      final d = armed();
      final r = run(d, [
        (0, 0.0, 55.0),
        (100, -0.9, 55.0), // rider leaves the bike
        (200, -0.9, 55.0),
        (300, 5.2, 40.0), // hits the ground
      ]);
      expect(r.last.state, CrashState.countdown);
      expect(r.last.impactAt, isNotNull);
      expect(r.last.secondsRemaining, CrashDetector.countdownSeconds);
      expect(r.last.peakG, greaterThanOrEqualTo(5.0));
    });

    test('a longer free-fall still fires', () {
      final d = armed();
      final r = <CrashDetection>[];
      r.add(d.update(
          now: t0, netG: 0.0, speedKmh: 60.0, isBike: true));
      for (var i = 1; i <= 30; i++) {
        r.add(d.update(
          now: t0.add(Duration(milliseconds: i * 50)),
          netG: -0.95,
          speedKmh: 60.0,
          isBike: true,
        ));
      }
      r.add(d.update(
        now: t0.add(const Duration(milliseconds: 1600)),
        netG: 6.0,
        speedKmh: 55.0,
        isBike: true,
      ));
      expect(r.last.state, CrashState.countdown);
    });

    test('the speed threshold is respected at the boundary', () {
      final d1 = armed();
      final below = run(d1, [
        (0, -0.9, 0.0),
        (150, -0.9, 0.0),
        (300, 5.0, 14.9),
      ]);
      expect(below.last.state, CrashState.normal,
          reason: '14.9 km/h is below the 15 km/h floor');

      final d2 = armed();
      final at = run(d2, [
        (0, -0.9, 0.0),
        (150, -0.9, 0.0),
        (300, 5.0, 15.0),
      ]);
      expect(at.last.state, CrashState.countdown);
    });

    test('the impact threshold is respected at the boundary', () {
      final d1 = armed();
      final below = run(d1, [
        (0, -0.9, 50.0),
        (150, -0.9, 50.0),
        (300, 3.4, 50.0),
      ]);
      expect(below.last.state, CrashState.normal,
          reason: '3.4 g is below the 3.5 g floor');

      final d2 = armed();
      final at = run(d2, [
        (0, -0.9, 50.0),
        (150, -0.9, 50.0),
        (300, 3.5, 50.0),
      ]);
      expect(at.last.state, CrashState.countdown);
    });

    test('a short free-fall glitch is not enough on its own', () {
      final d = armed();
      // 50 ms of free-fall, below the 120 ms hold.
      final r = run(d, [
        (0, -0.9, 50.0),
        (50, 5.0, 50.0),
        (100, 0.0, 50.0),
      ]);
      expect(r.every((s) => s.state == CrashState.normal), isTrue);
    });
  });

  group('CrashDetector — cancel and expiry', () {
    test('cancel returns to normal and clears the impact', () {
      final d = armed();
      run(d, [
        (0, -0.9, 50.0),
        (150, -0.9, 50.0),
        (300, 5.0, 50.0),
      ]);
      expect(d.state, CrashState.countdown);
      d.cancel();
      expect(d.state, CrashState.normal);

      // A subsequent normal sample must not resurrect it.
      final after = d.update(
        now: t0.add(const Duration(milliseconds: 400)),
        netG: 0.0,
        speedKmh: 50.0,
        isBike: true,
      );
      expect(after.state, CrashState.normal);
      expect(after.impactAt, isNull);
    });

    test('expire moves to expired, never to an auto-dispatch state', () {
      final d = armed();
      run(d, [
        (0, -0.9, 50.0),
        (150, -0.9, 50.0),
        (300, 5.0, 50.0),
      ]);
      d.expire();
      expect(d.state, CrashState.expired,
          reason: 'expiry logs the event; it must not dispatch anything');
    });

    test('expire on a normal state is a no-op', () {
      final d = armed();
      d.expire();
      expect(d.state, CrashState.normal);
    });

    test('arm resets all state', () {
      final d = armed();
      run(d, [
        (0, -0.9, 50.0),
        (150, -0.9, 50.0),
        (300, 5.0, 50.0),
      ]);
      expect(d.state, CrashState.countdown);
      d.arm();
      expect(d.state, CrashState.normal);
      expect(d.peakG, 0.0);
    });
  });

  group('CrashDetector — helpers', () {
    test('magnitude computes net acceleration magnitude', () {
      expect(CrashDetector.magnitude(0, 0, 9.81), closeTo(9.81, 0.001));
      expect(CrashDetector.magnitude(3, 4, 0), closeTo(5.0, 0.001));
    });
  });
}

/// Local sine so the test file needs no dart:math import.
double math_sin(double x) {
  // Only used at small arguments in this suite; Taylor terms converge fast.
  final x2 = x * x;
  return x * (1 - x2 / 6 + x2 * x2 / 120);
}