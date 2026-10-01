import 'dart:math';

class DynoPowerCalculator {
  // Honda PCX 160 + Rider average baseline:
  // Curb weight: 132 kg + Rider: 70 kg = 202 kg
  static const double defaultTotalMassKg = 202.0;
  static const double frontalAreaM2 = 0.65;
  static const double dragCoefficientCd = 0.75;
  static const double airDensityKgM3 = 1.205; // Sea level tropical ~30°C

  /// Calculates estimated instantaneous wheel horsepower (HP) and torque (Nm)
  static Map<String, double> estimatePowerAndTorque({
    required double speedKmh,
    required double accelerationMps2, // dV / dt
    required double rpm,
    double totalMassKg = defaultTotalMassKg,
  }) {
    if (speedKmh < 3.0 || accelerationMps2 <= 0.0) {
      return {'hp': 0.0, 'torqueNm': 0.0};
    }

    final double vMps = speedKmh / 3.6;

    // 1. Inertial Force: F_inertial = m * a
    final double fInertial = totalMassKg * accelerationMps2;

    // 2. Aerodynamic Drag Force: F_aero = 0.5 * rho * Cd * A * v^2
    final double fAero = 0.5 * airDensityKgM3 * dragCoefficientCd * frontalAreaM2 * (vMps * vMps);

    // 3. Rolling Resistance Force: F_roll = m * g * Cr (Cr ~ 0.018 for motorcycle tires)
    final double fRoll = totalMassKg * 9.81 * 0.018;

    final double totalForceN = fInertial + fAero + fRoll;

    // Power in Watts = Force * velocity
    final double powerWatts = totalForceN * vMps;

    // Convert Watts to Metric Horsepower (1 HP = 735.5 W)
    // Clamp to realistic PCX 160 max engine output (15.8 HP at crankshaft, ~12.5 HP at wheel)
    final double wheelHp = (powerWatts / 735.5).clamp(0.0, 16.5);

    // Wheel Torque in Nm = (Power in Watts) / (Wheel Angular Velocity in rad/s)
    // Or Engine Torque if RPM > 1000: Torque = (Power_W) / (2 * pi * RPM / 60)
    double torqueNm = 0.0;
    if (rpm > 1200.0) {
      final double omegaRadS = (2.0 * pi * rpm) / 60.0;
      torqueNm = (powerWatts / omegaRadS).clamp(0.0, 18.0);
    }

    return {
      'hp': double.parse(wheelHp.toStringAsFixed(1)),
      'torqueNm': double.parse(torqueNm.toStringAsFixed(1)),
    };
  }
}
