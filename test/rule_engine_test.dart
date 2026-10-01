import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/models/telemetry_data.dart';
import 'package:pcx_telemetry_app/core/rules/rule_engine.dart';
import 'package:pcx_telemetry_app/core/rules/trigger_rule.dart';
import 'package:pcx_telemetry_app/core/sensors/sensor_hub.dart';

RuleContext ctxWith({
  TelemetryFrame? frame,
  SensorHubData? sensor,
  bool obd = true,
  bool isBike = true,
  double? dteKm,
}) {
  return RuleContext(
    frame: frame ?? _frame(),
    sensor: sensor ?? _sensor(),
    obdConnected: obd,
    isBike: isBike,
    dteKm: dteKm,
  );
}

TelemetryFrame _frame({
  double rpm = 3000,
  double speed = 50,
  double ect = 70,
  double iat = 35,
  double battery = 12.6,
  double tps = 30,
  double fuelFlow = 1.2,
  double kml = 42,
}) {
  return TelemetryFrame(
    timestamp: DateTime.now(),
    rpm: rpm,
    speedKmh: speed,
    mapKpa: 40,
    ectC: ect,
    iatC: iat,
    tpsPercent: tps,
    batteryVoltage: battery,
    fuelFlowLh: fuelFlow,
    instantaneousKml: kml,
    leanAngleDeg: 0,
    gForce: 0,
  );
}

SensorHubData _sensor({
  double gpsSpeed = 50,
  double roll = 0,
  double g = 0,
  double slope = 0,
}) {
  return SensorHubData(
    latitude: -6.2,
    longitude: 106.8,
    altitude: 10,
    gpsSpeedKmh: gpsSpeed,
    headingDeg: 90,
    rollAngleDeg: roll,
    gForce: g,
    slopePercent: slope,
  );
}

void main() {
  const rule = TriggerRule(
    id: 'test_rule',
    label: 'Test',
    channel: RuleChannel.ectC,
    op: RuleOperator.greaterOrEqual,
    threshold: 100.0,
    holdMs: 1000,
    cooldownSec: 30,
    voiceMessage: 'uji',
  );

  group('TriggerRule.matches', () {
    test('greaterOrEqual is inclusive at the boundary', () {
      expect(rule.matches(100.0), isTrue);
      expect(rule.matches(99.9), isFalse);
    });

    test('greaterThan is exclusive at the boundary', () {
      const r = TriggerRule(
        id: 'x',
        label: 'x',
        channel: RuleChannel.ectC,
        op: RuleOperator.greaterThan,
        threshold: 100.0,
      );
      expect(r.matches(100.0), isFalse);
      expect(r.matches(100.1), isTrue);
    });

    test('rising needs a previous value and fires only on the crossing', () {
      const r = TriggerRule(
        id: 'x',
        label: 'x',
        channel: RuleChannel.ectC,
        op: RuleOperator.rising,
        threshold: 100.0,
      );
      expect(r.matches(120.0, previousValue: null), isFalse,
          reason: 'no edge without history');
      expect(r.matches(120.0, previousValue: 99.0), isTrue);
      expect(r.matches(120.0, previousValue: 110.0), isFalse,
          reason: 'already above, not a new crossing');
    });

    test('falling needs a previous value and fires only on the crossing', () {
      const r = TriggerRule(
        id: 'x',
        label: 'x',
        channel: RuleChannel.batteryVoltage,
        op: RuleOperator.falling,
        threshold: 11.7,
      );
      expect(r.matches(10.0, previousValue: null), isFalse);
      expect(r.matches(10.0, previousValue: 12.0), isTrue);
      expect(r.matches(10.0, previousValue: 11.0), isFalse);
    });
  });

  group('RuleEngine hold (hysteresis)', () {
    test('does not fire before holdMs has elapsed', () {
      final e = RuleEngine();
      final t0 = DateTime(2026, 1, 1, 12);

      final hot = ctxWith(frame: _frame(ect: 105));
      final r1 = e.evaluate(rules: [rule], ctx: hot, now: t0);
      expect(r1.fired, isEmpty, reason: 'condition true but hold just started');
      expect(r1.states[rule.id]!.armState, RuleArmState.pending);

      final r2 = e.evaluate(rules: [rule], ctx: hot, now: t0.add(Duration(milliseconds: 400)));
      expect(r2.fired, isEmpty, reason: 'still inside the 1000ms hold window');

      final r3 = e.evaluate(rules: [rule], ctx: hot, now: t0.add(Duration(milliseconds: 1200)));
      expect(r3.fired.length, 1, reason: 'hold satisfied');
      expect(r3.states[rule.id]!.armState, RuleArmState.armed);
    });

    test('a momentary spike shorter than holdMs never fires', () {
      final e = RuleEngine();
      final t0 = DateTime(2026, 1, 1, 12);
      final hot = ctxWith(frame: _frame(ect: 105));

      e.evaluate(rules: [rule], ctx: hot, now: t0);
      // Back to normal before the hold completes — GPS/IMU jitter shape.
      final r2 = e.evaluate(
          rules: [rule],
          ctx: ctxWith(frame: _frame(ect: 70)),
          now: t0.add(Duration(milliseconds: 300)));
      expect(r2.fired, isEmpty);
      expect(r2.states[rule.id]!.armState, RuleArmState.clear);

      // New spike must re-hold from scratch, not resume the old clock.
      e.evaluate(rules: [rule], ctx: hot, now: t0.add(Duration(milliseconds: 400)));
      final r4 = e.evaluate(
          rules: [rule],
          ctx: hot,
          now: t0.add(Duration(milliseconds: 900)));
      expect(r4.fired, isEmpty, reason: 'hold restarted after the blip cleared');
    });

    test('holdMs zero fires immediately', () {
      const instant = TriggerRule(
        id: 'i',
        label: 'i',
        channel: RuleChannel.ectC,
        op: RuleOperator.greaterOrEqual,
        threshold: 100.0,
        holdMs: 0,
      );
      final e = RuleEngine();
      final r = e.evaluate(
          rules: [instant], ctx: ctxWith(frame: _frame(ect: 110)),
          now: DateTime(2026, 1, 1));
      expect(r.fired.length, 1);
    });
  });

  group('RuleEngine cooldown', () {
    test('fires once, then stays silent until cooldown expires', () {
      final e = RuleEngine();
      final t0 = DateTime(2026, 1, 1, 12);
      final hot = ctxWith(frame: _frame(ect: 105));

      final r1 = e.evaluate(rules: [rule], ctx: hot, now: t0);
      expect(r1.fired, isEmpty);
      final firedAt = t0.add(Duration(milliseconds: 1200));
      final r2 = e.evaluate(rules: [rule], ctx: hot, now: firedAt);
      expect(r2.fired.length, 1);

      // Condition still true, but inside the 30s cooldown measured from when it
      // actually fired (t0+1.2s), not from t0.
      for (final offset in [2, 5, 15, 29]) {
        final at = firedAt.add(Duration(seconds: offset));
        if (at.isBefore(t0.add(Duration(seconds: 31)))) {
          final rr = e.evaluate(rules: [rule], ctx: hot, now: at);
          expect(rr.fired, isEmpty, reason: 'blocked at +${offset}s after firing');
          expect(rr.states[rule.id]!.armState, RuleArmState.armed,
              reason: 'still armed, just muted');
        }
      }

      final rEnd = e.evaluate(
          rules: [rule], ctx: hot, now: firedAt.add(Duration(seconds: 31)));
      expect(rEnd.fired.length, 1, reason: 're-alerted once the cooldown expired');
    });

    test('re-alert does NOT require the condition to drop and rise again', () {
      final e = RuleEngine();
      final t0 = DateTime(2026, 1, 1, 12);
      final hot = ctxWith(frame: _frame(ect: 105));

      e.evaluate(rules: [rule], ctx: hot, now: t0);
      final firedAt = t0.add(Duration(milliseconds: 1200));
      e.evaluate(rules: [rule], ctx: hot, now: firedAt);
      // Still hot 31s later: a rider parked at the rev limiter should be
      // reminded periodically, not left to guess.
      final r = e.evaluate(
          rules: [rule], ctx: hot, now: firedAt.add(Duration(seconds: 31)));
      expect(r.fired.length, 1);
    });
  });

  group('RuleEngine enable flag', () {
    test('a disabled rule never fires and reports clear', () {
      final e = RuleEngine();
      final off = rule.copyWith(enabled: false);
      final r = e.evaluate(
        rules: [off],
        ctx: ctxWith(frame: _frame(ect: 130)),
        now: DateTime(2026, 1, 1, 12),
      );
      expect(r.fired, isEmpty);
      expect(r.states[rule.id]!.armState, RuleArmState.clear);
    });

    test('enabling a rule requires a fresh hold', () {
      final e = RuleEngine();
      final off = rule.copyWith(enabled: false);
      final t0 = DateTime(2026, 1, 1, 12);
      final hot = ctxWith(frame: _frame(ect: 105));

      for (var i = 0; i < 5; i++) {
        e.evaluate(rules: [off], ctx: hot, now: t0.add(Duration(seconds: i)));
      }
      // User flips the switch on while the condition is already true.
      final r = e.evaluate(
        rules: [rule], ctx: hot, now: t0.add(Duration(seconds: 6)));
      expect(r.fired, isEmpty, reason: 'must not fire on the switch flip alone');
      final r2 = e.evaluate(
        rules: [rule], ctx: hot, now: t0.add(Duration(seconds: 8)));
      expect(r2.fired.length, 1);
    });
  });

  group('RuleContext channel availability', () {
    test('ECU channels read null while the dongle is disconnected', () {
      final ctx = ctxWith(obd: false, frame: _frame(ect: 999));
      expect(RuleChannel.ectC.read(ctx), isNull);
      expect(RuleChannel.batteryVoltage.read(ctx), isNull);
      expect(RuleChannel.rpm.read(ctx), isNull);
    });

    test('phone-sensor channels keep working without OBD', () {
      final ctx = ctxWith(obd: false, sensor: _sensor(gpsSpeed: 62, roll: 15));
      expect(RuleChannel.gpsSpeedKmh.read(ctx), 62);
      expect(RuleChannel.leanAngleDeg.read(ctx), 15);
    });

    test('speedKmh falls back to GPS when OBD is down', () {
      final ctx = ctxWith(obd: false, frame: _frame(speed: 10), sensor: _sensor(gpsSpeed: 62));
      expect(RuleChannel.speedKmh.read(ctx), 62,
          reason: 'must not alert on a stale 10 km/h ECU placeholder');
    });

    test('speedKmh prefers the ECU when connected', () {
      final ctx = ctxWith(obd: true, frame: _frame(speed: 88), sensor: _sensor(gpsSpeed: 62));
      expect(RuleChannel.speedKmh.read(ctx), 88);
    });

    test('lean reads null on a car profile', () {
      final ctx = ctxWith(isBike: false, sensor: _sensor(roll: 30));
      expect(RuleChannel.leanAngleDeg.read(ctx), isNull);
    });

    test('dteKm is null unless a real value is supplied', () {
      expect(RuleChannel.dteKm.read(ctxWith(dteKm: null)), isNull);
      expect(RuleChannel.dteKm.read(ctxWith(dteKm: 8.0)), 8.0);
    });

    test('a rule on an unavailable channel does not fire on placeholder zeros', () {
      final e = RuleEngine();
      const lowBatt = TriggerRule(
        id: 'low_batt',
        label: 'Aki',
        channel: RuleChannel.batteryVoltage,
        op: RuleOperator.lessThan,
        threshold: 11.7,
        holdMs: 0,
      );
      final t0 = DateTime(2026, 1, 1, 12);
      // OBD down: frame carries the empty() placeholder battery 12.5V. A naive
      // engine would still see 12.5 here; the real risk is a 0.0 placeholder
      // firing a "battery dead" alarm while riding.
      final r = e.evaluate(
          rules: [lowBatt], ctx: ctxWith(obd: false), now: t0);
      expect(r.fired, isEmpty);
      expect(r.states['low_batt']!.currentValue, isNull);
    });

    test('disconnecting mid-ride clears armed state so reconnect must re-hold', () {
      final e = RuleEngine();
      final t0 = DateTime(2026, 1, 1, 12);
      const hot = TriggerRule(
        id: 'overheat',
        label: 'Overheat',
        channel: RuleChannel.ectC,
        op: RuleOperator.greaterOrEqual,
        threshold: 100.0,
        holdMs: 1000,
      );

      e.evaluate(rules: [hot], ctx: ctxWith(frame: _frame(ect: 110)), now: t0);
      final armed = e.evaluate(
          rules: [hot],
          ctx: ctxWith(frame: _frame(ect: 110)),
          now: t0.add(Duration(milliseconds: 1100)));
      expect(armed.fired.length, 1);
      expect(armed.states['overheat']!.armState, RuleArmState.armed);

      // Dongle yanked. Fresh frame, ECT is garbage, state must not persist.
      final dropped = e.evaluate(
          rules: [hot], ctx: ctxWith(obd: false), now: t0.add(Duration(seconds: 2)));
      expect(dropped.states['overheat']!.armState, RuleArmState.clear);
      expect(dropped.states['overheat']!.currentValue, isNull);

      // Reconnected: one hour of overheating must not fire instantly.
      final reconnected = e.evaluate(
          rules: [hot],
          ctx: ctxWith(frame: _frame(ect: 110)),
          now: t0.add(Duration(seconds: 3)));
      expect(reconnected.fired, isEmpty, reason: 'fresh hold required');
    });
  });

  group('RuleEngine bookkeeping', () {
    test('resetRule forces a fresh hold', () {
      final e = RuleEngine();
      final t0 = DateTime(2026, 1, 1, 12);
      final hot = ctxWith(frame: _frame(ect: 105));

      e.evaluate(rules: [rule], ctx: hot, now: t0);
      e.evaluate(rules: [rule], ctx: hot, now: t0.add(Duration(milliseconds: 1200)));
      e.resetRule(rule.id);

      final r = e.evaluate(rules: [rule], ctx: hot, now: t0.add(Duration(seconds: 2)));
      expect(r.fired, isEmpty, reason: 'edited threshold must re-hold');
    });

    test('a rising rule does not fire on the very first frame after app start', () {
      const rising = TriggerRule(
        id: 'rise',
        label: 'Naik',
        channel: RuleChannel.ectC,
        op: RuleOperator.rising,
        threshold: 100.0,
        holdMs: 0,
      );
      final e = RuleEngine();
      final r = e.evaluate(
          rules: [rising],
          ctx: ctxWith(frame: _frame(ect: 130)),
          now: DateTime(2026, 1, 1, 12));
      expect(r.fired, isEmpty,
          reason: 'app launch must not immediately shout every rising rule');
    });

    test('multiple rules evaluate independently', () {
      final e = RuleEngine();
      const lean = TriggerRule(
        id: 'lean',
        label: 'Rebah',
        channel: RuleChannel.leanAngleDeg,
        op: RuleOperator.greaterOrEqual,
        threshold: 40.0,
        holdMs: 0,
      );
      const ect = TriggerRule(
        id: 'ect',
        label: 'ECT',
        channel: RuleChannel.ectC,
        op: RuleOperator.greaterOrEqual,
        threshold: 100.0,
        holdMs: 0,
      );
      final r = e.evaluate(
        rules: [lean, ect],
        ctx: ctxWith(frame: _frame(ect: 110), sensor: _sensor(roll: 45)),
        now: DateTime(2026, 1, 1, 12),
      );
      expect(r.fired.length, 2);
    });

    test('activeRuleIds reflects only armed rules', () {
      final e = RuleEngine();
      final t0 = DateTime(2026, 1, 1, 12);
      e.evaluate(rules: [rule], ctx: ctxWith(frame: _frame(ect: 105)), now: t0);
      expect(e.activeRuleIds, isEmpty, reason: 'pending is not armed');
      e.evaluate(
          rules: [rule],
          ctx: ctxWith(frame: _frame(ect: 105)),
          now: t0.add(Duration(milliseconds: 1200)));
      expect(e.activeRuleIds, contains(rule.id));
    });
  });

  group('TriggerRule serialization', () {
    test('round-trips through JSON', () {
      final json = rule.toJson();
      final back = TriggerRule.fromJson(json);
      expect(back, isNotNull);
      expect(back!.id, rule.id);
      expect(back.channel, rule.channel);
      expect(back.op, rule.op);
      expect(back.threshold, rule.threshold);
      expect(back.holdMs, rule.holdMs);
      expect(back.cooldownSec, rule.cooldownSec);
      expect(back.voiceMessage, rule.voiceMessage);
    });

    test('returns null on a corrupt entry instead of throwing', () {
      expect(TriggerRule.fromJson({'channel': 'notAChannel', 'op': 'greaterThan', 'threshold': 1}), isNull);
      expect(TriggerRule.fromJson({'channel': 'ectC', 'op': 'notAnOp', 'threshold': 1}), isNull);
      expect(TriggerRule.fromJson({'channel': 'ectC', 'op': 'greaterThan'}), isNull,
          reason: 'missing threshold');
      expect(TriggerRule.fromJson({'channel': 'ectC', 'op': 'greaterThan', 'threshold': 'hot'}), isNull);
    });

    test('every channel name round-trips', () {
      for (final ch in RuleChannel.values) {
        final r = rule.copyWith(channel: ch);
        final back = TriggerRule.fromJson(r.toJson());
        expect(back!.channel, ch, reason: 'channel ${ch.name} must round-trip');
      }
      for (final op in RuleOperator.values) {
        final r = rule.copyWith(op: op);
        final back = TriggerRule.fromJson(r.toJson());
        expect(back!.op, op, reason: 'operator ${op.name} must round-trip');
      }
    });
  });
}