import '../models/telemetry_data.dart';
import '../sensors/sensor_hub.dart';

/// Everything a rule may read, in one place.
///
/// Why this exists instead of passing [TelemetryFrame] + [SensorHubData] +
/// bools: derived values (DTE, economy) live outside both frames, and the
/// caller kept reaching for magic numbers to feed them — `main.dart` passed a
/// hardcoded `dteKm: 185.0` into the fuel alert. Making the context an explicit
/// type means a value the app fakes cannot silently reach an alarm.
class RuleContext {
  final TelemetryFrame frame;
  final SensorHubData sensor;
  final bool obdConnected;
  final bool isBike;

  /// Distance to Empty in km. Null when unknown — the fuel model has no tank
  /// float PID on commuter bikes and the app has no fill-to-fill history yet.
  final double? dteKm;

  final double movingAvgKml;

  const RuleContext({
    required this.frame,
    required this.sensor,
    required this.obdConnected,
    required this.isBike,
    this.dteKm,
    this.movingAvgKml = 0.0,
  });

  /// Real-time economy, preferring the ECU speed over GPS speed only when the
  /// dongle is actually connected.
  double? get effectiveSpeedKmh =>
      obdConnected ? frame.speedKmh : sensor.gpsSpeedKmh;
}

/// Telemetry channels a rule can watch.
///
/// Every channel resolves through [RuleChannel.read] — NOT a `Map<String,
/// dynamic>`. A map loses the compiler: renaming a field in TelemetryFrame
/// silently breaks every rule reading it, and the failure surfaces as a rule
/// that never fires while riding.
enum RuleChannel {
  speedKmh,
  gpsSpeedKmh,
  leanAngleDeg,
  ectC,
  iatC,
  batteryVoltage,
  tpsPercent,
  rpm,
  dteKm,
  gForce,
  slopePercent,
  fuelFlowLh,
  instantaneousKml;

  /// Channels that need the ECU. When the dongle is disconnected these read
  /// null and their rules are skipped, rather than firing against the 0.0
  /// placeholders in an empty TelemetryFrame.
  bool get requiresObd => const {
        RuleChannel.ectC,
        RuleChannel.iatC,
        RuleChannel.batteryVoltage,
        RuleChannel.tpsPercent,
        RuleChannel.rpm,
        RuleChannel.dteKm,
        RuleChannel.fuelFlowLh,
        RuleChannel.instantaneousKml,
      }.contains(this);

  /// Lean is a bike concept; on a car it is suspension roll noise.
  bool get bikeOnly => this == RuleChannel.leanAngleDeg;

  double? read(RuleContext ctx) {
    if (requiresObd && !ctx.obdConnected) return null;
    if (bikeOnly && !ctx.isBike) return null;

    switch (this) {
      case RuleChannel.speedKmh:
        return ctx.effectiveSpeedKmh;
      case RuleChannel.gpsSpeedKmh:
        return ctx.sensor.gpsSpeedKmh;
      case RuleChannel.leanAngleDeg:
        return ctx.sensor.rollAngleDeg;
      case RuleChannel.ectC:
        return ctx.frame.ectC;
      case RuleChannel.iatC:
        return ctx.frame.iatC;
      case RuleChannel.batteryVoltage:
        return ctx.frame.batteryVoltage;
      case RuleChannel.tpsPercent:
        return ctx.frame.tpsPercent;
      case RuleChannel.rpm:
        return ctx.frame.rpm;
      case RuleChannel.dteKm:
        return ctx.dteKm;
      case RuleChannel.gForce:
        return ctx.sensor.gForce;
      case RuleChannel.slopePercent:
        return ctx.sensor.slopePercent;
      case RuleChannel.fuelFlowLh:
        return ctx.frame.fuelFlowLh;
      case RuleChannel.instantaneousKml:
        return ctx.frame.instantaneousKml;
    }
  }
}

enum RuleOperator {
  greaterThan('>'),
  greaterOrEqual('>='),
  lessThan('<'),
  lessOrEqual('<='),
  rising('naik'),
  falling('turun');

  const RuleOperator(this.label);
  final String label;

  bool get needsHistory => this == rising || this == falling;
}

/// A single user-configurable alarm rule.
///
/// [holdMs] and [cooldownSec] are both anti-machine-gun, and they solve
/// different problems. `holdMs` is hysteresis: the condition must hold
/// continuously, so sensor jitter or a single GPS spike cannot fire it.
/// `cooldownSec` rate-limits a rule whose condition is still true — cornering
/// past the lean limit for 20 minutes should warn once, not every 20 seconds.
class TriggerRule {
  final String id;
  final String label;
  final RuleChannel channel;
  final RuleOperator op;
  final double threshold;
  final int holdMs;
  final int cooldownSec;
  final bool enabled;
  final String voiceMessage;

  const TriggerRule({
    required this.id,
    required this.label,
    required this.channel,
    required this.op,
    required this.threshold,
    this.holdMs = 1500,
    this.cooldownSec = 20,
    this.enabled = true,
    this.voiceMessage = '',
  });

  bool matches(double value, {double? previousValue}) {
    switch (op) {
      case RuleOperator.greaterThan:
        return value > threshold;
      case RuleOperator.greaterOrEqual:
        return value >= threshold;
      case RuleOperator.lessThan:
        return value < threshold;
      case RuleOperator.lessOrEqual:
        return value <= threshold;
      case RuleOperator.rising:
        // A crossing needs a defined starting point. With no previous sample
        // there is no edge, so the first frame after app start cannot fire
        // every rising rule at once.
        if (previousValue == null) return false;
        return previousValue < threshold && value >= threshold;
      case RuleOperator.falling:
        if (previousValue == null) return false;
        return previousValue > threshold && value <= threshold;
    }
  }

  TriggerRule copyWith({
    String? label,
    RuleChannel? channel,
    RuleOperator? op,
    double? threshold,
    int? holdMs,
    int? cooldownSec,
    bool? enabled,
    String? voiceMessage,
  }) {
    return TriggerRule(
      id: id,
      label: label ?? this.label,
      channel: channel ?? this.channel,
      op: op ?? this.op,
      threshold: threshold ?? this.threshold,
      holdMs: holdMs ?? this.holdMs,
      cooldownSec: cooldownSec ?? this.cooldownSec,
      enabled: enabled ?? this.enabled,
      voiceMessage: voiceMessage ?? this.voiceMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'channel': channel.name,
        'op': op.name,
        'threshold': threshold,
        'holdMs': holdMs,
        'cooldownSec': cooldownSec,
        'enabled': enabled,
        'voiceMessage': voiceMessage,
      };

  /// Returns null on anything unparseable instead of throwing — a corrupt
  /// SharedPreferences entry must never brick the cockpit on a handlebar mount.
  static TriggerRule? fromJson(Map<String, dynamic> json) {
    RuleChannel? ch;
    RuleOperator? op;
    for (final c in RuleChannel.values) {
      if (c.name == json['channel']) ch = c;
    }
    for (final o in RuleOperator.values) {
      if (o.name == json['op']) op = o;
    }
    final th = json['threshold'];
    if (ch == null || op == null || th is! num) return null;

    return TriggerRule(
      id: json['id']?.toString() ?? ch.name,
      label: json['label']?.toString() ?? '',
      channel: ch,
      op: op,
      threshold: th.toDouble(),
      holdMs: (json['holdMs'] as num?)?.toInt() ?? 1500,
      cooldownSec: (json['cooldownSec'] as num?)?.toInt() ?? 20,
      enabled: json['enabled'] as bool? ?? true,
      voiceMessage: json['voiceMessage']?.toString() ?? '',
    );
  }
}