import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/telemetry/speed_density_calculator.dart';
import 'package:pcx_telemetry_app/core/telemetry/battery_health_analyzer.dart';
import 'package:pcx_telemetry_app/core/telemetry/cvt_slip_detector.dart';

void main() {
  group('SpeedDensityCalculator Tests', () {
    const calc = SpeedDensityCalculator();

    test('Idle Fuel Flow calculation should be around 0.20 - 0.35 L/h', () {
      final fuelFlow = calc.calculateFuelFlowLh(
        rpm: 1500.0,
        mapKpa: 38.0,
        iatC: 35.0,
      );
      expect(fuelFlow, greaterThan(0.18));
      expect(fuelFlow, lessThan(0.35));
    });

    test('Cruising 50 km/h Economy should be around 35 - 50 km/L', () {
      final fuelFlow = calc.calculateFuelFlowLh(
        rpm: 5500.0,
        mapKpa: 60.0,
        iatC: 35.0,
      );
      final kml = calc.calculateEconomyKml(
        speedKmh: 50.0,
        fuelFlowLh: fuelFlow,
      );
      expect(kml, greaterThan(30.0));
      expect(kml, lessThan(55.0));
    });

    test('DTE Calculation should estimate distance proportional to remaining fuel', () {
      final dte = calc.calculateDteKm(
        currentFuelLevelL: 4.0,
        movingAvgKml: 45.0,
      );
      expect(dte, equals(180.0));
    });
  });

  group('BatteryHealthAnalyzer Tests', () {
    test('Cranking voltage >= 10.0V evaluates to healthy', () {
      final analyzer = BatteryHealthAnalyzer();
      analyzer.onEngineStartInitiated();
      analyzer.recordVoltageSample(10.5);
      analyzer.recordVoltageSample(10.2);
      final res = analyzer.evaluate(standbyVolt: 12.6);
      expect(res.condition, equals(BatteryCondition.healthy));
    });

    test('Cranking voltage < 9.5V evaluates to replace condition', () {
      final analyzer = BatteryHealthAnalyzer();
      analyzer.onEngineStartInitiated();
      analyzer.recordVoltageSample(9.1);
      final res = analyzer.evaluate(standbyVolt: 12.2);
      expect(res.condition, equals(BatteryCondition.replace));
    });
  });

  group('CvtSlipDetector Tests', () {
    test('Normal cruising does not trigger slip', () {
      final detector = CvtSlipDetector();
      final res = detector.evaluate(rpm: 5500.0, speedKmh: 50.0, tpsPercent: 40.0);
      expect(res.isSlipping, isFalse);
    });
  });
}
