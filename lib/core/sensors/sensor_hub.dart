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
  final double rollAngleDeg; // Lean angle (Left negative, Right positive)
  final double gForce;

  const SensorHubData({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.gpsSpeedKmh,
    required this.rollAngleDeg,
    required this.gForce,
  });

  factory SensorHubData.empty() => const SensorHubData(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 0.0,
        gpsSpeedKmh: 0.0,
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
  double _filteredRoll = 0.0;
  double _currentG = 0.0;

  // Low-pass filter smoothing coefficient (0.05 - 0.15 = buttery smooth against engine vibration)
  static const double _lpfAlpha = 0.10;
  // Deadband threshold in degrees around 0
  static const double _deadbandDeg = 1.5;

  SensorHubData get latestData => SensorHubData(
        latitude: _currentLat,
        longitude: _currentLng,
        altitude: _currentAlt,
        gpsSpeedKmh: _currentGpsSpeed,
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
          // pos.speed is in m/s; convert to km/h. Ignore negative speeds from invalid fixes.
          _currentGpsSpeed = pos.speed > 0 ? pos.speed * 3.6 : 0.0;
        });
      }
    } catch (e) {
      debugPrint('[SensorHub] GPS Error: $e');
    }

    // 2. Smooth Lean Angle from IMU Accelerometer
    try {
      _accelSub = accelerometerEventStream().listen((event) {
        // Motorcycle tilt logic:
        // When bike is upright on holder, gravity pulls down mostly along Y or Z.
        // Tilting left/right displaces gravity into X.
        final double magnitudeYZ =
            sqrt(event.y * event.y + event.z * event.z);
        final double rawRollRad = atan2(event.x, magnitudeYZ);
        double rawRollDeg = rawRollRad * (180.0 / pi);

        // Clamp to realistic motorcycle limits (-55° to +55°)
        rawRollDeg = rawRollDeg.clamp(-55.0, 55.0);

        // Low-pass filter (Exponential Moving Average)
        _filteredRoll =
            (_lpfAlpha * rawRollDeg) + ((1.0 - _lpfAlpha) * _filteredRoll);

        // Apply deadband around upright center
        if (_filteredRoll.abs() < _deadbandDeg) {
          _filteredRoll = 0.0;
        }

        // Net G-force calculation with smoothing
        final double netAcc = sqrt(event.x * event.x +
            event.y * event.y +
            event.z * event.z);
        final double rawG = (netAcc - 9.81) / 9.81;
        _currentG = (0.2 * rawG) + (0.8 * _currentG);
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
