import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../telemetry/lean_estimator.dart';

class SensorHubData {
  final double latitude;
  final double longitude;
  final double altitude;
  final double gpsSpeedKmh;
  final double headingDeg; // Direction of travel (0-360°)
  final double rollAngleDeg; // Lean angle (Left negative, Right positive)
  final double gForce;
  final double accelerationMps2; // Forward acceleration (dV/dt)
  final double slopePercent; // Incline gradient (+% climb, -% descent)
  final bool potholeDetected; // Road shock impulse event

  /// Sprint 2: IMU + GPS-geometry lean with provenance. Defaults to an
  /// `imuOnly` reading so a hand-built SensorHubData (tests, offline replay)
  /// never has to invent a GPS figure.
  final LeanReading lean;

  SensorHubData({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.gpsSpeedKmh,
    required this.headingDeg,
    required this.rollAngleDeg,
    required this.gForce,
    this.accelerationMps2 = 0.0,
    this.slopePercent = 0.0,
    this.potholeDetected = false,
    LeanReading? lean,
  }) : lean = lean ??
            LeanReading(imuDeg: rollAngleDeg, confidence: LeanConfidence.imuOnly);

  static SensorHubData empty() => SensorHubData(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 0.0,
        gpsSpeedKmh: 0.0,
        headingDeg: 0.0,
        rollAngleDeg: 0.0,
        gForce: 0.0,
        accelerationMps2: 0.0,
        slopePercent: 0.0,
        potholeDetected: false,
      );
}

class SensorHub {
  final StreamController<SensorHubData> _hubController =
      StreamController<SensorHubData>.broadcast();
  Stream<SensorHubData> get dataStream => _hubController.stream;

  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _emitThrottleTimer;
  Timer? _potholeClearTimer;

  double _currentLat = 0.0;
  double _currentLng = 0.0;
  double _currentAlt = 0.0;
  double _currentGpsSpeed = 0.0;
  double _currentHeading = 0.0;
  double _filteredRoll = 0.0;
  double _currentG = 0.0;

  double _accelerationMps2 = 0.0;
  double _slopePercent = 0.0;
  bool _potholeDetected = false;

  DateTime? _prevGpsTime;
  double _prevGpsSpeed = 0.0;
  double? _prevAltForSlope;
  double? _prevLatForSlope;
  double? _prevLngForSlope;

  /// Rolling window of the last 3 GPS fixes for corner-radius estimation.
  /// Sprint 2. A 3-point circumscribed circle is the minimum needed to
  /// resolve curvature; 2 points cannot distinguish a straight line from a
  /// gentle arc.
  final List<double> _latWindow = [];
  final List<double> _lngWindow = [];
  double _curvatureRadiusM = double.nan;

  bool _isLandscape = false;
  bool _enableLean = true;

  void setOrientation({required bool isLandscape}) {
    _isLandscape = isLandscape;
  }

  bool get _isPhoneLandscape {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
      if (view != null && view.physicalSize.width > 0 && view.physicalSize.height > 0) {
        return view.physicalSize.width > view.physicalSize.height;
      }
    } catch (_) {}
    return _isLandscape;
  }

  void setLeanEnabled(bool enabled) {
    _enableLean = enabled;
    if (!enabled) {
      _filteredRoll = 0.0;
      // A car has no lean angle. Clearing the curvature radius too means the
      // reading falls back to `imuOnly` at 0.0° rather than carrying a stale
      // motorcycle corner radius into the car profile.
      _curvatureRadiusM = double.nan;
    }
  }

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
        accelerationMps2: _accelerationMps2,
        slopePercent: _slopePercent,
        potholeDetected: _potholeDetected,
        lean: LeanEstimator.fromSources(
          imuDeg: _filteredRoll,
          speedKmh: _currentGpsSpeed,
          radiusM: _curvatureRadiusM.isNaN ? null : _curvatureRadiusM,
        ),
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
            distanceFilter: 0,
            forceLocationManager: false,
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
          final now = DateTime.now();
          _currentLat = pos.latitude;
          _currentLng = pos.longitude;
          _currentAlt = pos.altitude;
          final spd = pos.speed > 0 ? pos.speed * 3.6 : 0.0;
          _currentGpsSpeed = spd;

          // Forward acceleration calculation: a = (v2 - v1) / dt
          if (_prevGpsTime != null) {
            final double dt = now.difference(_prevGpsTime!).inMilliseconds / 1000.0;
            if (dt > 0.08 && dt < 1.0) {
              final double dv = (spd - _prevGpsSpeed) / 3.6; // m/s
              _accelerationMps2 = (0.3 * (dv / dt)) + (0.7 * _accelerationMps2);
            }
          }
          _prevGpsTime = now;
          _prevGpsSpeed = spd;

          // Road slope gradient calculation: (dAlt / dDist) * 100%
          if (_prevLatForSlope != null && _prevLngForSlope != null && _prevAltForSlope != null) {
            final double dist = Geolocator.distanceBetween(
              _prevLatForSlope!,
              _prevLngForSlope!,
              pos.latitude,
              pos.longitude,
            );
            if (dist >= 12.0) {
              final double dAlt = pos.altitude - _prevAltForSlope!;
              _slopePercent = ((dAlt / dist) * 100.0).clamp(-25.0, 25.0);
              _prevLatForSlope = pos.latitude;
              _prevLngForSlope = pos.longitude;
              _prevAltForSlope = pos.altitude;
            }
          } else {
            _prevLatForSlope = pos.latitude;
            _prevLngForSlope = pos.longitude;
            _prevAltForSlope = pos.altitude;
          }

          // Shortest-arc circular angle smoothing for heading
          if (spd > 2.0 && pos.heading >= 0.0) {
            final diff = ((pos.heading - _currentHeading + 180.0) % 360.0) - 180.0;
            _currentHeading = (_currentHeading + diff * 0.22) % 360.0;
            if (_currentHeading < 0) _currentHeading += 360.0;
          }

          // Sprint 2: corner radius from a 3-point circumscribed circle.
          _latWindow.add(pos.latitude);
          _lngWindow.add(pos.longitude);
          if (_latWindow.length > 3) {
            _latWindow.removeAt(0);
            _lngWindow.removeAt(0);
          }
          if (_latWindow.length == 3) {
            _curvatureRadiusM = LeanEstimator.radiusFromFixes(
                  lat1: _latWindow[0],
                  lon1: _lngWindow[0],
                  lat2: _latWindow[1],
                  lon2: _lngWindow[1],
                  lat3: _latWindow[2],
                  lon3: _lngWindow[2],
                ) ??
                double.nan;
          }
        });
      }
    } catch (e) {
      debugPrint('[SensorHub] GPS Error: $e');
    }

    // 2. Mathematically Exact Lean Angle + Pothole Shock Detector
    try {
      _accelSub = accelerometerEventStream().listen((event) {
        if (!_enableLean) {
          _filteredRoll = 0.0;
          return;
        }

        double rawRollRad = 0.0;
        final bool isLandscape = _isPhoneLandscape;

        if (!isLandscape) {
          // PORTRAIT: lateral roll moves gravity across phone X axis
          final double magnitudeYZ = sqrt(event.y * event.y + event.z * event.z);
          rawRollRad = -atan2(event.x, magnitudeYZ);
        } else {
          // LANDSCAPE: lateral roll moves gravity across phone Y axis
          final double magnitudeXZ = sqrt(event.x * event.x + event.z * event.z);
          if (event.x >= 0) {
            rawRollRad = atan2(event.y, magnitudeXZ);
          } else {
            rawRollRad = -atan2(event.y, magnitudeXZ);
          }
        }

        final double rawRollDeg = (rawRollRad * (180.0 / pi)).clamp(-55.0, 55.0);

        // Low-pass filter (Exponential Moving Average)
        final double smoothed =
            (_lpfAlpha * rawRollDeg) + ((1.0 - _lpfAlpha) * _filteredRoll);

        // Smooth deadband: exactly 0.0° when upright (<= 1.2°), seamlessly blends to exact reading by 3.5°
        final double absDeg = smoothed.abs();
        if (absDeg <= _deadbandDeg) {
          _filteredRoll = 0.0;
        } else if (absDeg >= _deadbandDeg + 2.5) {
          _filteredRoll = smoothed;
        } else {
          final double t = (absDeg - _deadbandDeg) / 2.5;
          final double blend = 3 * t * t - 2 * t * t * t;
          _filteredRoll = (smoothed > 0 ? 1.0 : -1.0) * (_deadbandDeg + blend * 2.5);
        }

        // Net G-force calculation with smoothing
        final double netAcc = sqrt(event.x * event.x +
            event.y * event.y +
            event.z * event.z);
        final double rawG = (netAcc - 9.81) / 9.81;
        _currentG = (0.15 * rawG) + (0.85 * _currentG);

        // Pothole Shock / Rough Road Detector:
        // Spike in net vertical shock while vehicle is moving > 10 km/h
        if (rawG.abs() >= 1.35 && _currentGpsSpeed > 10.0) {
          _potholeDetected = true;
          _potholeClearTimer?.cancel();
          _potholeClearTimer = Timer(const Duration(milliseconds: 1500), () {
            _potholeDetected = false;
          });
        }
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
    _potholeClearTimer?.cancel();
  }
}
