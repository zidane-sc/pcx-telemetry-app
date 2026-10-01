import 'dart:math' as math;

enum CrashState {
  /// Normal riding.
  normal,

  /// Free-fall detected (net G near zero). The device left the rider's hand.
  falling,

  /// Impact after a fall. A countdown to cancel is running.
  countdown,

  /// The countdown expired without confirmation. Logged, never auto-dispatched.
  expired,
}

class CrashDetection {
  final CrashState state;
  final double peakG;
  final DateTime? impactAt;

  /// Seconds left to cancel. Only meaningful in [CrashState.countdown].
  final int secondsRemaining;

  const CrashDetection({
    required this.state,
    required this.peakG,
    this.impactAt,
    this.secondsRemaining = 0,
  });

  bool get isActive => state != CrashState.normal;
}

/// Detects a crash from IMU + GPS, with a cancel window.
///
/// The signature of a real motorcycle fall is a **free-fall followed by an
/// impact**, not just a spike. Engine vibration and potholes produce high-G
/// events all day; a pothole never produces zero-G. Requiring the free-fall
/// phase first is what separates a crash from a bad road, and it is the same
/// reasoning that makes the existing pothole detector tolerable.
///
/// `ponytail:` the countdown never auto-dispatches an SOS. A false positive
/// dialling an emergency contact is worse than a missed crash: the rider can
/// still confirm, and the event is logged either way. Upgrade to a
/// medical-grade algorithm (accelerometer + gyroscope + barometer) only if a
/// real crash was missed.
class CrashDetector {
  /// Net acceleration below this fraction of g counts as free-fall.
  static const double freeFallG = 0.35;

  /// How long free-fall must persist to be credible. Sensor glitches are short.
  /// Reached either by elapsed time or by the second consecutive free-fall
  /// sample. Two is the honest floor: one sample of low-G is routinely produced
  /// by a bump compressing the accelerometer, while a rider actually leaving
  /// the bike produces sustained near-zero-G across at least two ticks at the
  /// app's 15 Hz emit rate.
  static const int freeFallHoldMs = 120;
  static const int freeFallMinSamples = 2;

  /// Impact must exceed this many g after a free-fall.
  static const double impactG = 3.5;

  /// Seconds a rider has to cancel before the event is logged.
  static const int countdownSeconds = 10;

  /// Grace after unlock/cold start. A phone placed on a seat while the bike
  /// is being moved produces violent shaking that is not a crash.
  static final Duration armGrace = const Duration(seconds: 8);

  /// Below this speed there is no crash to speak of — the bike did not move.
  static const double minImpactSpeedKmh = 15.0;

  CrashState _state = CrashState.normal;
  DateTime? _freeFallSince;
  int _freeFallSamples = 0;
  DateTime? _impactAt;
  double _peakG = 0.0;
  DateTime? _armedAt;

  CrashState get state => _state;
  double get peakG => _peakG;

  /// Called once when a trip or ride begins, so the grace period starts from a
  /// known moment rather than app launch.
  void arm({DateTime? now}) {
    _armedAt = now ?? DateTime.now();
    _state = CrashState.normal;
    _freeFallSince = null;
    _freeFallSamples = 0;
    _impactAt = null;
    _peakG = 0.0;
  }

  void reset() {
    _state = CrashState.normal;
    _freeFallSince = null;
    _freeFallSamples = 0;
    _impactAt = null;
    _peakG = 0.0;
  }

  /// The rider confirmed they are OK, or dismissed the alert.
  void cancel() {
    _state = CrashState.normal;
    _freeFallSince = null;
    _freeFallSamples = 0;
    _impactAt = null;
  }

  /// Feeds one IMU + GPS sample.
  ///
  /// [netG] is `(sqrt(x²+y²+z²) - 9.81) / 9.81` as the existing pothole
  /// detector computes it: 0 at rest, negative in free-fall, large on impact.
  CrashDetection update({
    required DateTime now,
    required double netG,
    required double speedKmh,
    required bool isBike,
    bool armed = true,
  }) {
    // A car profile has no lean telemetry and its crash dynamics differ; the
    // honest thing is to not claim to detect car crashes at all.
    if (!isBike) return _report();

    if (!armed) return _report();

    final a = _armedAt;
    if (a != null && now.difference(a) < armGrace) {
      return _report();
    }

    final absG = netG.abs();
    if (absG > _peakG) _peakG = absG;

    // Phase 1: free-fall.
    if (netG < -freeFallG && _state == CrashState.normal) {
      _freeFallSince ??= now;
      _freeFallSamples++;
      final heldMs = now.difference(_freeFallSince!).inMilliseconds;
      if (heldMs >= freeFallHoldMs || _freeFallSamples >= freeFallMinSamples) {
        _state = CrashState.falling;
      }
      return _report();
    }

    // Not free-falling and not yet falling: the free-fall window closes.
    if (netG >= -freeFallG && _state == CrashState.normal) {
      _freeFallSince = null;
      _freeFallSamples = 0;
    }

    // Phase 2: impact, but only if free-fall was actually observed first and
    // the bike was moving. A parked phone being knocked over is not a crash.
    if (_state == CrashState.falling && _impactAt == null) {
      if (netG >= impactG && speedKmh >= minImpactSpeedKmh) {
        _state = CrashState.countdown;
        _impactAt = now;
        return CrashDetection(
          state: _state,
          peakG: _peakG,
          impactAt: _impactAt,
          secondsRemaining: countdownSeconds,
        );
      }
      // Free-fall resolved without an impact: the rider dropped the phone in
      // a pocket. Reset rather than leaving the detector latched.
      if (netG > -freeFallG) {
        _state = CrashState.normal;
        _freeFallSince = null;
        _freeFallSamples = 0;
      }
    }

    return _report();
  }

  /// The rider did not cancel in time. Callers log the event; nothing is
  /// dispatched automatically.
  void expire() {
    if (_state == CrashState.countdown) _state = CrashState.expired;
  }

  CrashDetection _report() {
    final impact = _impactAt;
    var remaining = 0;
    if (_state == CrashState.countdown && impact != null) {
      remaining = countdownSeconds;
    }
    return CrashDetection(
      state: _state,
      peakG: _peakG,
      impactAt: impact,
      secondsRemaining: remaining,
    );
  }

  /// Lateral + longitudinal G magnitude a rider actually feels, for the
  /// existing pothole detector's display.
  static double magnitude(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);
}