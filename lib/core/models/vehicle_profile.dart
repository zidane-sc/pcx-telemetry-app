enum VehicleType { motorcycle, car }

enum ObdProtocolType {
  auto('0', 'Auto Select'),
  kwp2000Fast('5', 'ISO 14230-4 KWP (Fast Init 10.4k)'),
  can11bit500k('6', 'ISO 15765-4 CAN (11-bit 500k)'),
  can29bit500k('7', 'ISO 15765-4 CAN (29-bit 500k)');

  final String atspValue;
  final String label;
  const ObdProtocolType(this.atspValue, this.label);
}

enum FuelCalculationMethod {
  speedDensity, // For engines without direct MAF (Honda PCX, bikes)
  mafDirect,    // For cars with direct MAF sensor (Toyota Yaris)
}

class VehicleProfile {
  final String id;
  final String name;
  final VehicleType type;
  final String plateNumber;
  final double engineCc;
  final double tankCapacityL;
  final String fuelType;
  final double fuelPricePerL;
  final ObdProtocolType protocol;
  final FuelCalculationMethod fuelMethod;
  final bool hasLeanSensor;
  final double veFactor;
  final double baseOdometerKm;

  const VehicleProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.plateNumber,
    required this.engineCc,
    required this.tankCapacityL,
    required this.fuelType,
    this.fuelPricePerL = 12950.0,
    required this.protocol,
    required this.fuelMethod,
    required this.hasLeanSensor,
    this.veFactor = 0.82,
    this.baseOdometerKm = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'plateNumber': plateNumber,
        'engineCc': engineCc,
        'tankCapacityL': tankCapacityL,
        'fuelType': fuelType,
        'fuelPricePerL': fuelPricePerL,
        'protocol': protocol.name,
        'fuelMethod': fuelMethod.name,
        'hasLeanSensor': hasLeanSensor,
        'veFactor': veFactor,
        'baseOdometerKm': baseOdometerKm,
      };

  factory VehicleProfile.fromJson(Map<String, dynamic> json) => VehicleProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        type: VehicleType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => VehicleType.motorcycle,
        ),
        plateNumber: json['plateNumber'] as String? ?? '',
        engineCc: (json['engineCc'] as num?)?.toDouble() ?? 150.0,
        tankCapacityL: (json['tankCapacityL'] as num?)?.toDouble() ?? 8.0,
        fuelType: json['fuelType'] as String? ?? 'Pertamax 92',
        fuelPricePerL: (json['fuelPricePerL'] as num?)?.toDouble() ?? 12950.0,
        protocol: ObdProtocolType.values.firstWhere(
          (e) => e.name == json['protocol'],
          orElse: () => ObdProtocolType.kwp2000Fast,
        ),
        fuelMethod: FuelCalculationMethod.values.firstWhere(
          (e) => e.name == json['fuelMethod'],
          orElse: () => FuelCalculationMethod.speedDensity,
        ),
        hasLeanSensor: json['hasLeanSensor'] as bool? ?? true,
        veFactor: (json['veFactor'] as num?)?.toDouble() ?? 0.82,
        baseOdometerKm: (json['baseOdometerKm'] as num?)?.toDouble() ?? 0.0,
      );

  // Preset for Honda PCX 160
  static const VehicleProfile defaultPcx160 = VehicleProfile(
    id: 'pcx_160',
    name: 'Honda PCX 160 eSP+ ABS',
    type: VehicleType.motorcycle,
    plateNumber: 'B 1234 SC',
    engineCc: 156.9,
    tankCapacityL: 8.1,
    fuelType: 'Pertamax 92',
    fuelPricePerL: 12950.0,
    protocol: ObdProtocolType.kwp2000Fast,
    fuelMethod: FuelCalculationMethod.speedDensity,
    hasLeanSensor: true,
    veFactor: 0.82,
    baseOdometerKm: 0.0,
  );

  // Preset for Toyota Yaris 2014
  static const VehicleProfile defaultYaris2014 = VehicleProfile(
    id: 'yaris_2014',
    name: 'Toyota Yaris 2014 1.5 E',
    type: VehicleType.car,
    plateNumber: 'B 2014 SC',
    engineCc: 1497.0,
    tankCapacityL: 42.0,
    fuelType: 'Pertamax 92',
    fuelPricePerL: 12950.0,
    protocol: ObdProtocolType.can11bit500k,
    fuelMethod: FuelCalculationMethod.mafDirect,
    hasLeanSensor: false, // Mobil tidak butuh lean angle
    veFactor: 0.85,
    baseOdometerKm: 85000.0,
  );
}
