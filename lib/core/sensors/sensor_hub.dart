import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorHubData {
  final double latitude;
  final double longitude;
  final double altitude;
  final double gpsSpeedKmh;
  final double headingDeg; // Direction of travel (0-360°)
  final double rollAngleDeg; // Lean angle (Left negative, Right positive)
  final double gForce;

  const SensorHubData({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.gpsSpeedKmh,
    required this.headingDeg,
    required this.rollAngleDeg,
    required this.gForce,
  });

  factory SensorHubData.empty() => const SensorHubData(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 0.0,
        gpsSpeedKmh: 0.0,
        headingDeg: 0.0,
        rollAngleDeg: 0.0,
        gForce: 0.0,
      );
}

class SensorHub {
  final StreamController<SensorHubData> _hubController =
      StreamController<SensorHubData>.broadcast();
  Stream<SensorHubData> get dataStream => _hubController.stream;

  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _emitThrottleTimer;

  double _currentLat = 0.0;
  double _currentLng = 0.0;
  double _currentAlt = 0.0;
  double _currentGpsSpeed = 0.0;
  double _currentHeading = 0.0;
  double _filteredRoll = 0.0;
  double _currentG = 0.0;

  // Low-pass filter smoothing coefficient (0.08 = ultra smooth against engine vibration)
  static const double _lpfAlpha = 0.08;
  // Soft deadband threshold in degrees around 0
  static const double _deadbandDeg = 1.2;

  SensorHubData get latestData => SensorHubData(
        latitude: _currentLat,
        longitude: _currentLng,
        altitude: _currentAlt,
        gpsSpeedKmh: _currentGpsSpeed,
        headingDeg: _currentHeading,
        rollAngleDeg: _filteredRoll,
        gForce: _currentG,
      );

  Future<void> start() async {
    // 1. High-frequency real-time GPS stream (5 Hz / 200ms)
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        late final LocationSettings locationSettings;

        if (defaultTargetPlatform == TargetPlatform.android) {
          locationSettings = AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0, // Real-time continuous updates
            forceLocationManager: false, // High-frequency FusedLocationProvider
            intervalDuration: const Duration(milliseconds: 200), // 5 Hz
          );
        } else {
          locationSettings = const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          );
        }

        _gpsSub = Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((pos) {
          _currentLat = pos.latitude;
          _currentLng = pos.longitude;
          _currentAlt = pos.altitude;
          final spd = pos.speed > 0 ? pos.speed * 3.6 : 0.0;
          _currentGpsSpeed = spd;

          // Shortest-arc circular angle smoothing for heading (no snapping across North 0°/360°)
          if (spd > 2.0 && pos.heading >= 0.0) {
            final diff = ((pos.heading - _currentHeading + 180.0) % 360.0) - 180.0;
            _currentHeading = (_currentHeading + diff * 0.22) % 360.0;
            if (_currentHeading < 0) _currentHeading += 360.0;
          }
        });
      }
    } catch (e) {
      debugPrint('[SensorHub] GPS Error: $e');
    }

    // 2. Smooth Lean Angle from IMU Accelerometer with soft deadband
    try {
      _accelSub = accelerometerEventStream().listen((event) {
        final double magnitudeYZ =
            sqrt(event.y * event.y + event.z * event.z);
        final double rawRollRad = atan2(event.x, magnitudeYZ);
        // Negate so that tilting left produces negative (LEFT) and tilting right produces positive (RIGHT)
        double rawRollDeg = -rawRollRad * (180.0 / pi);

        // Clamp to realistic motorcycle lean limits (-55° to +55°)
        rawRollDeg = rawRollDeg.clamp(-55.0, 55.0);

        // Low-pass filter (Exponential Moving Average)
        final double smoothed =
            (_lpfAlpha * rawRollDeg) + ((1.0 - _lpfAlpha) * _filteredRoll);

        // Continuous soft deadband around upright center (no abrupt steps)
        if (smoothed.abs() <= _deadbandDeg) {
          _filteredRoll = 0.0;
        } else {
          _filteredRoll = (smoothed > 0)
              ? (smoothed - _deadbandDeg)
              : (smoothed + _deadbandDeg);
        }

        // Net G-force calculation with smoothing
        final double netAcc = sqrt(event.x * event.x +
            event.y * event.y +
            event.z * event.z);
        final double rawG = (netAcc - 9.81) / 9.81;
        _currentG = (0.15 * rawG) + (0.85 * _currentG);
      });
    } catch (e) {
      debugPrint('[SensorHub] IMU Error: $e');
    }

    // 3. Steady 15 Hz stream emitter (every 66ms) to prevent UI flooding
    _emitThrottleTimer?.cancel();
    _emitThrottleTimer =
        Timer.periodic(const Duration(milliseconds: 66), (_) {
      _hubController.add(latestData);
    });
  }

  void stop() {
    _gpsSub?.cancel();
    _accelSub?.cancel();
    _emitThrottleTimer?.cancel();
  }
}
