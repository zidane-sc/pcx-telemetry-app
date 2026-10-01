import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/telemetry/engine_brake_detector.dart';

void main() {
  DateTime t0 = DateTime(2026, 1, 1, 12);

  /// Feeds a linear ramp of (time, speed, rpm, tps) at the app's 15 Hz emit
  /// rate, so the sliding window sees what it really sees in the field.
  void ramp(
    EngineBrakeDetector d, {
    required int ticks,
    required double startKmh,
    required double endKmh,
    required double startRpm,
    required double endRpm,
    required double tps,
    bool obd = true,
  }) {
    final stepMs = 66; // ~15 Hz
    for (var i = 0; i < ticks; i++) {
      final f = ticks == 1 ? 0.0 : i / (ticks - 1);
      d.update(
        now: t0.add(Duration(milliseconds: stepMs * i)),
        speedKmh: startKmh + (endKmh - startKmh) * f,
        rpm: startRpm + (endRpm - startRpm) * f,
        tpsPercent: tps,
        obdConnected: obd,
      );
    }
    t0 = t0.add(Duration(milliseconds: stepMs * ticks));
  }

  group('EngineBrakeDetector — classification', () {
    test('closed throttle + falling RPM + held speed is engine braking', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      // 60 -> 58 km/h over 1s (slope -2... too fast, use gentler)
      ramp(d,
          ticks: 16,
          startKmh: 60.0,
          endKmh: 59.0,
          startRpm: 7000.0,
          endRpm: 5000.0,
          tps: 0.0);

      expect(d.isEngineBraking, isTrue);
      expect(d.engineBrakeCount, 1);
      expect(d.serviceBrakeCount, 0);
    });

    test('service braking is classified separately', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      // Speed genuinely dropping fast, RPM following down.
      ramp(d,
          ticks: 16,
          startKmh: 60.0,
          endKmh: 45.0,
          startRpm: 7000.0,
          endRpm: 4000.0,
          tps: 0.0);

      expect(d.serviceBrakeCount, 1);
      expect(d.engineBrakeCount, 0);
      expect(d.isEngineBraking, isFalse);
    });

    test('throttle open means never engine braking, even with falling RPM', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      ramp(d,
          ticks: 16,
          startKmh: 60.0,
          endKmh: 59.0,
          startRpm: 7000.0,
          endRpm: 5000.0,
          tps: 40.0);

      expect(d.isEngineBraking, isFalse);
      expect(d.engineBrakeCount, 0);
    });

    test('steady cruise is coasting, not engine braking', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      ramp(d,
          ticks: 20,
          startKmh: 50.0,
          endKmh: 50.0,
          startRpm: 5500.0,
          endRpm: 5500.0,
          tps: 30.0);

      expect(d.isEngineBraking, isFalse);
      expect(d.engineBrakeCount, 0);
      expect(d.serviceBrakeCount, 0);
    });

    test('acceleration is classified as accelerating', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      ramp(d,
          ticks: 16,
          startKmh: 40.0,
          endKmh: 60.0,
          startRpm: 4000.0,
          endRpm: 7000.0,
          tps: 60.0);

      // The last event should be accelerating.
      final e = d.update(
        now: t0,
        speedKmh: 62.0,
        rpm: 7200.0,
        tpsPercent: 60.0,
      );
      expect(e.classification, DecelClass.accelerating);
    });

    test('too slow to classify — clutch open, RPM decoupled', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      ramp(d,
          ticks: 16,
          startKmh: 10.0,
          endKmh: 9.0,
          startRpm: 2500.0,
          endRpm: 1500.0,
          tps: 0.0);

      expect(d.engineBrakeCount, 0,
          reason: 'below minSpeedKmh the drivetrain is not coupled');
      expect(d.isEngineBraking, isFalse);
    });

    test('no ECU means no classification, never a fabricated RPM slope', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      ramp(d,
          ticks: 16,
          startKmh: 60.0,
          endKmh: 59.0,
          startRpm: 7000.0,
          endRpm: 5000.0,
          tps: 0.0,
          obd: false);

      expect(d.engineBrakeCount, 0);
      expect(d.serviceBrakeCount, 0);
      expect(d.isEngineBraking, isFalse);
    });
  });

  group('EngineBrakeDetector — event counting', () {
    test('one physical downshift increments exactly once', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      // 4 seconds of continuous engine braking.
      ramp(d,
          ticks: 60,
          startKmh: 60.0,
          endKmh: 58.0,
          startRpm: 7500.0,
          endRpm: 5000.0,
          tps: 0.0);

      expect(d.engineBrakeCount, 1,
          reason: 'one continuous manoeuvre, one event');
      expect(d.engineBrakeSeconds, greaterThan(2.5));
    });

    test('the cooldown blocks a second count inside the window', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      // First event: 60 -> 59 km/h, 7000 -> 5200 rpm, closed throttle.
      ramp(d,
          ticks: 30,
          startKmh: 60.0,
          endKmh: 59.0,
          startRpm: 7000.0,
          endRpm: 5200.0,
          tps: 0.0);
      expect(d.engineBrakeCount, 1);

      // Coast at the RPM the bike actually settled at. Jumping the RPM back up
      // would pollute the 1s sliding window with a huge positive slope and
      // delay the next downshift past the cooldown — testing the wrong thing.
      ramp(d,
          ticks: 15,
          startKmh: 59.0,
          endKmh: 59.0,
          startRpm: 5200.0,
          endRpm: 5200.0,
          tps: 30.0);

      // Second, separate downshift 1.98s after the first — inside the 3.5s
      // cooldown, so it must be suppressed.
      ramp(d,
          ticks: 20,
          startKmh: 59.0,
          endKmh: 58.2,
          startRpm: 5200.0,
          endRpm: 4400.0,
          tps: 0.0);

      expect(d.engineBrakeCount, 1,
          reason: 'second downshift inside the 3.5s cooldown is suppressed');
    });

    test('after the cooldown a new downshift counts again', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      ramp(d,
          ticks: 30,
          startKmh: 60.0,
          endKmh: 59.0,
          startRpm: 7000.0,
          endRpm: 5200.0,
          tps: 0.0);
      expect(d.engineBrakeCount, 1);

      // Coast well past the cooldown.
      ramp(d,
          ticks: 90,
          startKmh: 59.0,
          endKmh: 59.0,
          startRpm: 5200.0,
          endRpm: 5200.0,
          tps: 30.0);

      ramp(d,
          ticks: 30,
          startKmh: 59.0,
          endKmh: 58.0,
          startRpm: 7000.0,
          endRpm: 5200.0,
          tps: 0.0);

      expect(d.engineBrakeCount, 2);
    });

    test('brake and engine-brake counts stay independent', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      // Hard brake.
      ramp(d,
          ticks: 20,
          startKmh: 60.0,
          endKmh: 40.0,
          startRpm: 7000.0,
          endRpm: 3500.0,
          tps: 0.0);
      expect(d.serviceBrakeCount, 1);

      // Coast past cooldown.
      ramp(d,
          ticks: 90,
          startKmh: 40.0,
          endKmh: 40.0,
          startRpm: 3500.0,
          endRpm: 3500.0,
          tps: 30.0);

      // Engine brake.
      ramp(d,
          ticks: 30,
          startKmh: 40.0,
          endKmh: 39.0,
          startRpm: 6000.0,
          endRpm: 4500.0,
          tps: 0.0);

      expect(d.serviceBrakeCount, 1);
      expect(d.engineBrakeCount, 1);
    });
  });

  group('EngineBrakeDetector — intensity', () {
    test('a gentle downshift reads lower intensity than a hard one', () {
          // gentle: -120 rpm/s (exactly the threshold) -> intensity ~0.5
          // hard:   -2000 rpm/s -> clamped to 1.0
          final gentle = EngineBrakeDetector();
          gentle.update(
            now: t0.subtract(const Duration(milliseconds: 1000)),
            speedKmh: 60.0,
            rpm: 5920.0,
            tpsPercent: 0.0,
          );
          final gentleEvent = gentle.update(
            now: t0,
            speedKmh: 60.0,
            rpm: 5800.0,
            tpsPercent: 0.0,
          );

          final hard = EngineBrakeDetector();
          hard.update(
            now: t0.subtract(const Duration(milliseconds: 1000)),
            speedKmh: 60.0,
            rpm: 7000.0,
            tpsPercent: 0.0,
          );
          final hardEvent = hard.update(
            now: t0,
            speedKmh: 60.0,
            rpm: 5000.0,
            tpsPercent: 0.0,
          );

          expect(gentleEvent.classification, DecelClass.engineBraking);
          expect(hardEvent.classification, DecelClass.engineBraking);
          expect(hardEvent.intensity, greaterThan(gentleEvent.intensity));
          expect(hardEvent.intensity, lessThanOrEqualTo(1.0));
          expect(gentleEvent.intensity, greaterThan(0.0));
        });

        test('the very first tick reports zero intensity (no history yet)', () {
          final d = EngineBrakeDetector();
          final first = d.update(
            now: t0,
            speedKmh: 60.0,
            rpm: 6000.0,
            tpsPercent: 0.0,
          );
          expect(first.intensity, 0.0,
              reason: 'a slope needs two samples; the first tick has none');
          expect(first.classification, DecelClass.coasting);
        });
  });

  group('EngineBrakeDetector — trip state', () {
    test('reset clears all counters', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();
      ramp(d,
          ticks: 40,
          startKmh: 60.0,
          endKmh: 58.0,
          startRpm: 7000.0,
          endRpm: 5000.0,
          tps: 0.0);
      expect(d.engineBrakeCount, greaterThan(0));

      d.reset();
      expect(d.engineBrakeCount, 0);
      expect(d.serviceBrakeCount, 0);
      expect(d.engineBrakeSeconds, 0.0);
      expect(d.isEngineBraking, isFalse);
    });

    test('adoptCounts restores a loaded trip', () {
      final d = EngineBrakeDetector();
      d.adoptCounts(engineBrakes: 7, serviceBrakes: 3, engineBrakeSecs: 42.5);
      expect(d.engineBrakeCount, 7);
      expect(d.serviceBrakeCount, 3);
      expect(d.engineBrakeSeconds, 42.5);
    });

    test('sub-second blips do not accumulate time', () {
      t0 = DateTime(2026, 1, 1, 12);
      final d = EngineBrakeDetector();

      // A 200ms flicker of engine braking, then back to coast.
      ramp(d,
          ticks: 3,
          startKmh: 60.0,
          endKmh: 59.5,
          startRpm: 6000.0,
          endRpm: 5400.0,
          tps: 0.0);
      ramp(d,
          ticks: 30,
          startKmh: 59.5,
          endKmh: 59.5,
          startRpm: 5400.0,
          endRpm: 5400.0,
          tps: 30.0);

      expect(d.engineBrakeSeconds, 0.0,
          reason: 'a 200ms flicker is sensor noise, not a downshift');
    });
  });
}