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

  double _currentLat = 0.0;
  double _currentLng = 0.0;
  double _currentAlt = 0.0;
  double _currentGpsSpeed = 0.0;
  double _currentRoll = 0.0;
  double _currentG = 0.0;

  SensorHubData get latestData => SensorHubData(
        latitude: _currentLat,
        longitude: _currentLng,
        altitude: _currentAlt,
        gpsSpeedKmh: _currentGpsSpeed,
        rollAngleDeg: _currentRoll,
        gForce: _currentG,
      );

  Future<void> start() async {
    // Start GPS stream
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        _gpsSub = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2,
          ),
        ).listen((pos) {
          _currentLat = pos.latitude;
          _currentLng = pos.longitude;
          _currentAlt = pos.altitude;
          _currentGpsSpeed = pos.speed * 3.6; // m/s to km/h
          _emit();
        });
      }
    } catch (e) {
      debugPrint('[SensorHub] GPS Error: $e');
    }

    // Start IMU Accelerometer stream for Lean Angle
    try {
      _accelSub = accelerometerEventStream().listen((event) {
        // Phone mounted in landscape or portrait on motorcycle holder:
        // Calculate roll tilt angle using arctan2(x, z)
        final double rollRad = atan2(event.x, event.z);
        _currentRoll = rollRad * (180.0 / pi);

        // Calculate net G-force
        final double netAcc =
            sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        _currentG = (netAcc - 9.81) / 9.81;

        _emit();
      });
    } catch (e) {
      debugPrint('[SensorHub] IMU Error: $e');
    }
  }

  void _emit() {
    _hubController.add(latestData);
  }

  void stop() {
    _gpsSub?.cancel();
    _accelSub?.cancel();
  }
}
