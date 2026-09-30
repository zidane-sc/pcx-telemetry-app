import '../constants/api_constants.dart';

class SpeedDensityCalculator {
  final double displacementL;
  final double volumetricEfficiency;
  final double airFuelRatio;
  final double gasolineDensityGL;

  const SpeedDensityCalculator({
    this.displacementL = ApiConstants.pcxDisplacementL,
    this.volumetricEfficiency = ApiConstants.pcxVolumetricEfficiency,
    this.airFuelRatio = 14.7,
    this.gasolineDensityGL = 745.0,
  });

  /// Calculates instantaneous Fuel Flow Rate in Liters per Hour (L/h)
  double calculateFuelFlowLh({
    required double rpm,
    required double mapKpa,
    required double iatC,
  }) {
    if (rpm <= 0 || mapKpa <= 0) return 0.0;

    // Convert IAT from Celsius to Kelvin
    final double tKelvin = iatC + 273.15;

    // Displaced volume rate in m^3/s for a 4-stroke single cylinder engine:
    // V_rate = (displacement in m^3) * (RPM / (2 * 60))
    final double vRateM3s = (displacementL * 1e-3) * (rpm / 120.0);

    // Pressure in Pascals: MAP (kPa) * 1000
    final double pPa = mapKpa * 1000.0;

    // Air Mass Flow rate (g/s) using Ideal Gas Law (PV = m/M * RT)
    // M_air = 28.97 g/mol, R = 8.314 J/(mol*K)
    final double airMassGs =
        (pPa * vRateM3s * 28.97 / (8.314 * tKelvin)) * volumetricEfficiency;

    // Fuel Mass Flow (g/s)
    final double fuelMassGs = airMassGs / airFuelRatio;

    // Fuel Volume Flow (L/h) = (g/s * 3600) / (density in g/L)
    final double fuelFlowLh = (fuelMassGs * 3600.0) / gasolineDensityGL;

    return fuelFlowLh;
  }

  /// Calculates instantaneous Fuel Economy in km/L
  /// If vehicle is stationary (speed < 2 km/h), returns 0.0 (app should display L/h instead)
  double calculateEconomyKml({
    required double speedKmh,
    required double fuelFlowLh,
  }) {
    if (speedKmh < 2.0 || fuelFlowLh <= 0.0) {
      return 0.0;
    }
    return speedKmh / fuelFlowLh;
  }

  /// Estimates Distance to Empty (DTE) in kilometers
  double calculateDteKm({
    required double currentFuelLevelL,
    required double movingAvgKml,
  }) {
    if (currentFuelLevelL <= 0 || movingAvgKml <= 0) return 0.0;
    return currentFuelLevelL * movingAvgKml;
  }

  /// Estimates trip fuel cost in IDR
  double calculateTripCostIdr({
    required double fuelConsumedL,
    double pricePerLiter = ApiConstants.defaultFuelPriceIdr,
  }) {
    return fuelConsumedL * pricePerLiter;
  }
}
