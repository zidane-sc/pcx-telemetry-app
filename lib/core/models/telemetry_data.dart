/// A value the ECU can actually report.
///
/// Doubles as the validity set on [TelemetryFrame]. An ELM327 returns
/// `NO DATA`, `?`, or nothing at all for a PID the ECU does not implement,
/// and the honest response is to say so rather than to keep a plausible
/// default — a commuter PCX has no fuel-level float and often no odometer
/// PID, and a gauge showing `75%` or `12345 km` for a sensor that does not
/// exist is worse than a dash.
enum ObdChannel {
  rpm,
  speed,
  map,
  tps,
  engineLoad,
  timingAdvance,
  ect,
  iat,
  batteryVoltage,
  fuelLevel,
  ecuOdometer,
}

class TelemetryFrame {
  final DateTime timestamp;
  final double rpm;
  final double speedKmh;
  final double mapKpa;
  final double ectC;
  final double iatC;
  final double tpsPercent;
  final double batteryVoltage;
  final double fuelFlowLh;
  final double instantaneousKml;
  final double leanAngleDeg;
  final double gForce;

  // Rich ECU Telemetry Data
  final double engineLoadPercent; // 0104: 0-100%
  final double timingAdvanceDeg;  // 010E: Ignition timing degrees (-64 to +64°)
  final double fuelLevelPercent;   // 012F: 0-100% (cars / supported ECUs)
  final double ecuOdometerKm;     // 01A6: ECU physical odometer if supported

  /// Which of the above the ECU actually answered on this cycle.
  ///
  /// Empty means the dongle is not connected at all. Partial means it is
  /// connected and this particular PID is unsupported — a normal state on a
  /// motorcycle, not a fault. Consumers must check before displaying.
  final Set<ObdChannel> live;

  const TelemetryFrame({
    required this.timestamp,
    required this.rpm,
    required this.speedKmh,
    required this.mapKpa,
    required this.ectC,
    required this.iatC,
    required this.tpsPercent,
    required this.batteryVoltage,
    required this.fuelFlowLh,
    required this.instantaneousKml,
    required this.leanAngleDeg,
    required this.gForce,
    this.engineLoadPercent = 0.0,
    this.timingAdvanceDeg = 10.0,
    this.fuelLevelPercent = 0.0,
    this.ecuOdometerKm = 0.0,
    this.live = const {},
  });

  bool has(ObdChannel c) => live.contains(c);

  factory TelemetryFrame.empty() {
    return TelemetryFrame(
      timestamp: DateTime.now(),
      rpm: 0.0,
      speedKmh: 0.0,
      mapKpa: 101.3,
      ectC: 30.0,
      iatC: 30.0,
      tpsPercent: 0.0,
      batteryVoltage: 12.5,
      fuelFlowLh: 0.0,
      instantaneousKml: 0.0,
      leanAngleDeg: 0.0,
      gForce: 0.0,
      engineLoadPercent: 0.0,
      timingAdvanceDeg: 10.0,
      fuelLevelPercent: 0.0,
      ecuOdometerKm: 0.0,
      live: const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'rpm': rpm,
        'speedKmh': speedKmh,
        'mapKpa': mapKpa,
        'ectC': ectC,
        'iatC': iatC,
        'tpsPercent': tpsPercent,
        'batteryVoltage': batteryVoltage,
        'fuelFlowLh': fuelFlowLh,
        'instantaneousKml': instantaneousKml,
        'leanAngleDeg': leanAngleDeg,
        'gForce': gForce,
        'engineLoadPercent': engineLoadPercent,
        'timingAdvanceDeg': timingAdvanceDeg,
        'fuelLevelPercent': fuelLevelPercent,
        'ecuOdometerKm': ecuOdometerKm,
        'live': live.map((c) => c.name).toList(),
      };
}
