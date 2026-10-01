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
  });

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
  };
}
