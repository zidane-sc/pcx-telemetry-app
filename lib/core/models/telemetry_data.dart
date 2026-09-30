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
  };
}
