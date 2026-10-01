/// How a deceleration event should be classified.
enum DecelClass {
  /// Speed is rising.
  accelerating,

  /// Neither accelerating nor decelerating.
  coasting,

  /// Throttle closed, RPM falling faster than road speed: the ECU is dragging
  /// the drivetrain to slow the bike. Distinct from a service brake.
  engineBraking,

  /// Road speed is genuinely dropping — the rider is on the brakes.
  serviceBraking,
}

class DecelEvent {
  final DecelClass classification;
  final double intensity; // 0..1
  final double rpmSlopePerSec;
  final double speedSlopeKmhPerSec;

  const DecelEvent({
    required this.classification,
    required this.intensity,
    required this.rpmSlopePerSec,
    required this.speedSlopeKmhPerSec,
  });

  bool get isEngineBraking => classification == DecelClass.engineBraking;
  bool get isServiceBraking => classification == DecelClass.serviceBraking;
  bool get isDeceleration =>
      classification == DecelClass.engineBraking ||
      classification == DecelClass.serviceBraking;
}

/// Classifies each tick as acceleration, coast, engine braking or service
/// braking, and counts *events* rather than ticks.
///
/// Pure and clock-injected: the caller passes an explicit `now`, so cooldown
/// and sliding-window behaviour are unit-testable without a fake clock or a
/// Stream.
///
/// Physics: engine braking is the ECU applying negative torque to slow the
/// crankshaft. Three things are true at once:
///   1. the rider has closed the throttle (`tps` low),
///   2. RPM is falling fast (the crankshaft is being dragged down), and
///   3. road speed is roughly *held* — the bike is not actually slowing down
///      much, because the engine drag is doing the work.
///
/// A service brake instead shows road speed dropping. That third condition is
/// the whole discriminator: a rider braking hard and downshifting at the same
/// time does both, and the road-speed term decides which it was.
///
/// `ponytail:` thresholds are calibrated for a 156.9 cc commuter CVT bike.
/// A rider with a big multi-cylinder engine may need different numbers — the
/// fields are public so they can be tuned without touching the logic.
class EngineBrakeDetector {
  /// Throttle at or below this counts as closed. A CVT blip on a closed
  /// throttle sits a few percent open; anything above is the rider asking for
  /// power.
  final double closedThrottlePercent;

  /// RPM must be falling at least this fast (rpm/s) for the crankshaft to
  /// count as being dragged down.
  final double minRpmDropPerSec;

  /// Road speed may still fall up to this much (km/h/s) and the event is
  /// still engine braking. Beyond it, the rider is on the brakes.
  final double maxSpeedDropKmhPerSec;

  /// Speed must be above this for the classification to be meaningful —
  /// at a standstill the clutch is open and RPM is decoupled from road speed.
  final double minSpeedKmh;

  /// One physical deceleration must increment the counter exactly once.
  final Duration eventCooldown;

  /// Sliding window used to derive slopes.
  static const Duration window = Duration(milliseconds: 1000);

  int _engineBrakeCount = 0;
  int _serviceBrakeCount = 0;
  double _engineBrakeSeconds = 0.0;
  DateTime? _lastEventAt;
  bool _inEngineBraking = false;

  /// Last tick the engine-brake hold was flushed into [_engineBrakeSeconds].
  DateTime? _lastFlushAt;

  int get engineBrakeCount => _engineBrakeCount;
  int get serviceBrakeCount => _serviceBrakeCount;
  double get engineBrakeSeconds => _engineBrakeSeconds;

  /// True while the current tick is classified as engine braking. Drives the
  /// cockpit EB pill.
  bool get isEngineBraking => _inEngineBraking;

  EngineBrakeDetector({
    this.closedThrottlePercent = 15.0,
    this.minRpmDropPerSec = 120.0,
    this.maxSpeedDropKmhPerSec = 1.5,
    this.minSpeedKmh = 15.0,
    this.eventCooldown = const Duration(milliseconds: 3500),
  });

  /// Drops all accumulated trip state. Call when a trip ends.
  void reset() {
    _engineBrakeCount = 0;
    _serviceBrakeCount = 0;
    _engineBrakeSeconds = 0.0;
    _lastEventAt = null;
    _inEngineBraking = false;
    _lastFlushAt = null;
  }

  /// Keeps rolling counters in sync with a restored trip record.
  void adoptCounts({
    required int engineBrakes,
    required int serviceBrakes,
    required double engineBrakeSecs,
  }) {
    _engineBrakeCount = engineBrakes;
    _serviceBrakeCount = serviceBrakes;
    _engineBrakeSeconds = engineBrakeSecs;
  }

  /// Classifies one telemetry tick and updates the event counters.
  ///
  /// [rpm] and [tps] require a live ECU. When [obdConnected] is false the
  /// engine cannot be observed at all, so this returns [DecelClass.coasting]
  /// and counts nothing — rather than inventing an RPM slope.
  DecelEvent update({
    required DateTime now,
    required double speedKmh,
    required double rpm,
    required double tpsPercent,
    bool obdConnected = true,
  }) {
    if (!obdConnected) {
      _inEngineBraking = false;
      return DecelEvent(
        classification: DecelClass.coasting,
        intensity: 0.0,
        rpmSlopePerSec: 0.0,
        speedSlopeKmhPerSec: 0.0,
      );
    }

    // Sliding window: keep only samples inside the last second so the slope
    // reflects the last ~5 ticks at the 15 Hz emit rate.
    _samples.removeWhere(
        (s) => now.difference(s.time) > window);
    _samples.add(_Sample(now, rpm, speedKmh));
    if (_samples.length > 40) {
      _samples.removeAt(0);
    }

    if (_samples.length < 2 || speedKmh < minSpeedKmh) {
      // Not enough history to call a slope, or too slow for the drivetrain to
      // be coupled. Either way there is no event to count.
      _inEngineBraking = false;
      return DecelEvent(
        classification: DecelClass.coasting,
        intensity: 0.0,
        rpmSlopePerSec: 0.0,
        speedSlopeKmhPerSec: 0.0,
      );
    }

    final oldest = _samples.first;
    final dtSec = now.difference(oldest.time).inMilliseconds / 1000.0;
    if (dtSec <= 0.05) {
      return DecelEvent(
        classification: DecelClass.coasting,
        intensity: 0.0,
        rpmSlopePerSec: 0.0,
        speedSlopeKmhPerSec: 0.0,
      );
    }

    final double rpmSlope = (rpm - oldest.rpm) / dtSec;
    final double speedSlope = (speedKmh - oldest.speedKmh) / dtSec;

    DecelClass cls;
    if (speedSlope > 0.5) {
      cls = DecelClass.accelerating;
    } else if (rpmSlope <= -minRpmDropPerSec &&
        tpsPercent <= closedThrottlePercent &&
        speedSlope >= -maxSpeedDropKmhPerSec) {
      cls = DecelClass.engineBraking;
    } else if (speedSlope <= -maxSpeedDropKmhPerSec) {
      cls = DecelClass.serviceBraking;
    } else {
      cls = DecelClass.coasting;
    }

    _updateCounters(cls, now);

    // Intensity: how hard the crankshaft is being dragged, normalised against
    // twice the threshold so a 120 rpm/s drag reads ~0.5 and 240 reads ~1.0.
    final double intensity = cls == DecelClass.engineBraking
        ? (rpmSlope.abs() / (minRpmDropPerSec * 2.0)).clamp(0.0, 1.0)
        : (speedSlope.abs() / 6.0).clamp(0.0, 1.0);

    return DecelEvent(
      classification: cls,
      intensity: intensity,
      rpmSlopePerSec: rpmSlope,
      speedSlopeKmhPerSec: speedSlope,
    );
  }

  void _updateCounters(DecelClass cls, DateTime now) {
    final bool cooling =
        _lastEventAt != null && now.difference(_lastEventAt!) <= eventCooldown;

    if (cls == DecelClass.engineBraking) {
      // A continuous hold is ONE manoeuvre, however long it lasts. The event
      // is stamped on the rising edge of the classification and never
      // re-stamped while the classification stays the same — so a 6-second
      // downhill engine-brake counts once, not twice just because it outlasted
      // the 3.5 s cooldown.
      if (!_inEngineBraking) {
        if (!cooling) {
          _engineBrakeCount++;
          _lastEventAt = now;
        }
        _lastFlushAt = now;
      } else {
        // Accumulate the hold live so the figure is correct even if the ride
        // ends, the app is killed, or a bracket is still open when the rider
        // stops. Waiting for the classification to end loses all of it.
        _engineBrakeSeconds +=
            now.difference(_lastFlushAt!).inMilliseconds / 1000.0;
      }
      _lastFlushAt = now;
      _inEngineBraking = true;
    } else if (cls == DecelClass.serviceBraking) {
      if (_inEngineBraking && _lastFlushAt != null) {
        _engineBrakeSeconds +=
            now.difference(_lastFlushAt!).inMilliseconds / 1000.0;
      }
      _inEngineBraking = false;
      _lastFlushAt = null;
      if (!cooling) {
        _serviceBrakeCount++;
        _lastEventAt = now;
      }
    } else {
      if (_inEngineBraking && _lastFlushAt != null) {
        _engineBrakeSeconds +=
            now.difference(_lastFlushAt!).inMilliseconds / 1000.0;
      }
      _inEngineBraking = false;
      _lastFlushAt = null;
      if (cls == DecelClass.accelerating) {
        _lastEventAt = now;
      }
    }
  }

  final List<_Sample> _samples = [];
}

class _Sample {
  final DateTime time;
  final double rpm;
  final double speedKmh;
  const _Sample(this.time, this.rpm, this.speedKmh);
}