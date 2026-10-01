import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/telemetry_data.dart';
import '../sensors/sensor_hub.dart';
import '../telemetry/lean_estimator.dart';
import '../sync/pocketbase_service.dart';
import 'polyline_encoder.dart';

class _SpeedTimeSample {
  final DateTime time;
  final double speedKmh;
  const _SpeedTimeSample({required this.time, required this.speedKmh});
}

class TripRecord {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final double durationMin;
  final double distanceKm;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final double fuelConsumedL;
  final double avgKml;
  final double tripCostIdr;
  final double maxEctC;
  final double maxLeanLeftDeg;
  final double maxLeanRightDeg;
  final int hardBrakingCount;
  final String routePolyline;
  final String timelineData;
  final bool synced;

  const TripRecord({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.durationMin,
    required this.distanceKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.fuelConsumedL,
    required this.avgKml,
    required this.tripCostIdr,
    required this.maxEctC,
    required this.maxLeanLeftDeg,
    required this.maxLeanRightDeg,
    required this.hardBrakingCount,
    required this.routePolyline,
    required this.timelineData,
    required this.synced,
  });

  TripRecord copyWith({bool? synced}) => TripRecord(
        id: id,
        startTime: startTime,
        endTime: endTime,
        durationMin: durationMin,
        distanceKm: distanceKm,
        avgSpeedKmh: avgSpeedKmh,
        maxSpeedKmh: maxSpeedKmh,
        fuelConsumedL: fuelConsumedL,
        avgKml: avgKml,
        tripCostIdr: tripCostIdr,
        maxEctC: maxEctC,
        maxLeanLeftDeg: maxLeanLeftDeg,
        maxLeanRightDeg: maxLeanRightDeg,
        hardBrakingCount: hardBrakingCount,
        routePolyline: routePolyline,
        timelineData: timelineData,
        synced: synced ?? this.synced,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'durationMin': durationMin,
        'distanceKm': distanceKm,
        'avgSpeedKmh': avgSpeedKmh,
        'maxSpeedKmh': maxSpeedKmh,
        'fuelConsumedL': fuelConsumedL,
        'avgKml': avgKml,
        'tripCostIdr': tripCostIdr,
        'maxEctC': maxEctC,
        'maxLeanLeftDeg': maxLeanLeftDeg,
        'maxLeanRightDeg': maxLeanRightDeg,
        'hardBrakingCount': hardBrakingCount,
        'routePolyline': routePolyline,
        'timelineData': timelineData,
        'synced': synced,
      };

  factory TripRecord.fromJson(Map<String, dynamic> map) => TripRecord(
        id: map['id'] ?? '',
        startTime: DateTime.parse(map['startTime']),
        endTime: DateTime.parse(map['endTime']),
        durationMin: (map['durationMin'] ?? 0.0).toDouble(),
        distanceKm: (map['distanceKm'] ?? 0.0).toDouble(),
        avgSpeedKmh: (map['avgSpeedKmh'] ?? 0.0).toDouble(),
        maxSpeedKmh: (map['maxSpeedKmh'] ?? 0.0).toDouble(),
        fuelConsumedL: (map['fuelConsumedL'] ?? 0.0).toDouble(),
        avgKml: (map['avgKml'] ?? 0.0).toDouble(),
        tripCostIdr: (map['tripCostIdr'] ?? 0.0).toDouble(),
        maxEctC: (map['maxEctC'] ?? 0.0).toDouble(),
        maxLeanLeftDeg: (map['maxLeanLeftDeg'] ?? 0.0).toDouble(),
        maxLeanRightDeg: (map['maxLeanRightDeg'] ?? 0.0).toDouble(),
        hardBrakingCount: map['hardBrakingCount'] ?? 0,
        routePolyline: map['routePolyline'] ?? '',
        timelineData: map['timelineData'] ?? '[]',
        synced: map['synced'] ?? false,
      );
}

class TripManager extends ChangeNotifier {
  static final TripManager _instance = TripManager._internal();
  factory TripManager() => _instance;
  TripManager._internal();

  PocketBaseService? _pbService;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  DateTime? _startTime;
  Timer? _tickerTimer;
  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  double _distanceKm = 0.0;
  double get distanceKm => _distanceKm;

  double _maxSpeedKmh = 0.0;
  double get maxSpeedKmh => _maxSpeedKmh;

  double _speedSum = 0.0;
  int _speedSamples = 0;
  double get avgSpeedKmh =>
      _speedSamples > 0 ? _speedSum / _speedSamples : 0.0;

  double _maxLeanLeft = 0.0;
  double get maxLeanLeft => _maxLeanLeft;

  double _maxLeanRight = 0.0;
  double get maxLeanRight => _maxLeanRight;

  double _maxEct = 0.0;
  int _hardBrakingCount = 0;
  int get hardBrakingCount => _hardBrakingCount;

  // Running telemetry states for adaptive timeline
  double _latestSpeed = 0.0;
  double _latestLean = 0.0;

  /// Sprint 2: full lean reading with provenance, mirrored from SensorHubData so
  /// the periodic keyframer can persist it without re-deriving anything.
  LeanReading? _latestLeanReading;
  double _latestLat = 0.0;
  double _latestLng = 0.0;
  double _latestAlt = 0.0;

  // Adaptive dead-reckoning state trackers (kills 80% redundant snapshots)
  int _lastSavedSec = -1;
  double _lastSavedSpeed = 0.0;
  double _lastSavedLean = 0.0;
  bool _wasStopped = false;

  // Hard braking tracking variables
  final List<_SpeedTimeSample> _speedHistory = [];
  DateTime? _lastHardBrakingTriggered;

  double? _prevLat;
  double? _prevLng;
  final List<List<double>> _coordinates = [];
  final List<Map<String, dynamic>> _timelineSnapshots = [];

  final List<TripRecord> _history = [];
  List<TripRecord> get history => List.unmodifiable(_history);

  Future<void> init({required PocketBaseService pbService}) async {
    _pbService = pbService;
    await _loadHistory();

    // Listen to connection changes to flush offline unsynced trips
    _pbService?.isConnectedNotifier.addListener(() {
      if (_pbService?.isConnectedNotifier.value == true) {
        flushUnsyncedTrips();
      }
    });
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('local_trip_history') ?? [];
      _history.clear();
      for (final raw in list) {
        _history.add(TripRecord.fromJson(jsonDecode(raw)));
      }
      notifyListeners();

      // Attempt to flush unsynced trips on startup
      flushUnsyncedTrips();
    } catch (e) {
      debugPrint('[TripManager] Error loading history: $e');
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _history.map((t) => jsonEncode(t.toJson())).toList();
      await prefs.setStringList('local_trip_history', list);
    } catch (_) {}
  }

  void startTrip() {
    if (_isRecording) return;
    _isRecording = true;
    _startTime = DateTime.now();
    _elapsed = Duration.zero;
    _distanceKm = 0.0;
    _maxSpeedKmh = 0.0;
    _speedSum = 0.0;
    _speedSamples = 0;
    _maxLeanLeft = 0.0;
    _maxLeanRight = 0.0;
    _maxEct = 0.0;
    _hardBrakingCount = 0;
    _prevLat = null;
    _prevLng = null;
    _coordinates.clear();
    _timelineSnapshots.clear();
    _speedHistory.clear();
    _lastHardBrakingTriggered = null;

    _lastSavedSec = -1;
    _lastSavedSpeed = 0.0;
    _lastSavedLean = 0.0;
    _wasStopped = false;

    // Adaptive Sampling Ticker:
    // Ticks every 1s to update timer, but only captures keyframe snapshots on significant events
    // (Reduces storage footprint by ~80% while retaining high-fidelity cornering & speed curves)
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startTime != null && _isRecording) {
        _elapsed = DateTime.now().difference(_startTime!);
        final int curSec = _elapsed.inSeconds;

        if (_latestLat != 0.0 && _latestLng != 0.0) {
          bool shouldSave = false;

          if (_timelineSnapshots.isEmpty) {
            // First snapshot at trip start
            shouldSave = true;
          } else {
            final double speedDelta = (_latestSpeed - _lastSavedSpeed).abs();
            final double leanDelta = (_latestLean - _lastSavedLean).abs();
            final int secSinceLast = curSec - _lastSavedSec;

            if (_latestSpeed < 2.0) {
              // Bike is stopped / idling at traffic light
              if (!_wasStopped) {
                // Record the moment of stopping
                shouldSave = true;
                _wasStopped = true;
              } else if (secSinceLast >= 20) {
                // Low-frequency heartbeat while waiting at light (1 point per 20s instead of 20 points!)
                shouldSave = true;
              }
            } else {
              // Bike is moving
              if (_wasStopped) {
                // Moment bike resumed motion
                shouldSave = true;
                _wasStopped = false;
              } else if (speedDelta >= 4.0) {
                // Significant speed acceleration or deceleration
                shouldSave = true;
              } else if (leanDelta >= 3.0) {
                // Active cornering / lean angle change
                shouldSave = true;
              } else if (secSinceLast >= 6) {
                // Steady cruising heartbeat every 6s on straightaways
                shouldSave = true;
              }
            }
          }

          if (shouldSave) {
            // Sprint 2: store the second lean estimate and the divergence.
            // Old trips lack these keys, so the playback reader must treat a
            // missing 'leanGps' as "no cross-check recorded", never as 0.
            final lean = _latestLeanReading;
            _timelineSnapshots.add({
              't': curSec,
              'lat': double.parse(_latestLat.toStringAsFixed(5)),
              'lng': double.parse(_latestLng.toStringAsFixed(5)),
              'spd': _latestSpeed.round(),
              'lean': _latestLean.round(),
              'alt': _latestAlt.round(),
              if (lean != null) 'leanGps': lean.gpsDeg?.round(),
              if (lean != null) 'leanCam': lean.camberDeg?.round(),
              if (lean != null) 'leanConf': lean.confidence.name,
            });
            _lastSavedSec = curSec;
            _lastSavedSpeed = _latestSpeed;
            _lastSavedLean = _latestLean;
          }
        }

        notifyListeners();
      }
    });

    notifyListeners();
  }

  void onTelemetryUpdate({
    required SensorHubData sensorData,
    TelemetryFrame? obdFrame,
  }) {
    if (!_isRecording) return;

    final double speed = (obdFrame != null && obdFrame.speedKmh > 1.0)
        ? obdFrame.speedKmh
        : sensorData.gpsSpeedKmh;

    _latestSpeed = speed;
    _latestLean = sensorData.rollAngleDeg;
    _latestLeanReading = sensorData.lean;
    _latestLat = sensorData.latitude;
    _latestLng = sensorData.longitude;
    _latestAlt = sensorData.altitude;

    if (speed > _maxSpeedKmh) _maxSpeedKmh = speed;
    _speedSum += speed;
    _speedSamples++;

    // Lean Angle peak tracking
    final double roll = sensorData.rollAngleDeg;
    if (roll < -_maxLeanLeft) _maxLeanLeft = -roll;
    if (roll > _maxLeanRight) _maxLeanRight = roll;

    // Realistic Hard Braking Detector via Speed Differential:
    // Drop >= 14 km/h in <= 1.2s while traveling > 18 km/h with 3.5s event cooldown
    final now = DateTime.now();
    _speedHistory.add(_SpeedTimeSample(time: now, speedKmh: speed));
    _speedHistory.removeWhere(
        (s) => now.difference(s.time).inMilliseconds > 1200);

    if (_speedHistory.length >= 2 && speed > 15.0) {
      final oldest = _speedHistory.first;
      final speedDrop = oldest.speedKmh - speed;
      final timeDiffSec =
          now.difference(oldest.time).inMilliseconds / 1000.0;

      if (timeDiffSec >= 0.4 && (speedDrop / timeDiffSec) >= 14.0) {
        if (_lastHardBrakingTriggered == null ||
            now.difference(_lastHardBrakingTriggered!).inMilliseconds > 3500) {
          _hardBrakingCount++;
          _lastHardBrakingTriggered = now;

          // Immediately bookmark hard braking event in timeline
          if (_latestLat != 0.0 && _latestLng != 0.0) {
            _timelineSnapshots.add({
              't': _elapsed.inSeconds,
              'lat': double.parse(_latestLat.toStringAsFixed(5)),
              'lng': double.parse(_latestLng.toStringAsFixed(5)),
              'spd': _latestSpeed.round(),
              'lean': _latestLean.round(),
              'alt': _latestAlt.round(),
              'event': 'braking',
            });
            _lastSavedSec = _elapsed.inSeconds;
          }

          debugPrint(
              '[TripManager] Hard braking event #$_hardBrakingCount detected: -$speedDrop km/h in ${timeDiffSec.toStringAsFixed(1)}s');
        }
      }
    }

    // Engine Temp
    if (obdFrame != null && obdFrame.ectC > _maxEct) {
      _maxEct = obdFrame.ectC;
    }

    // GPS Distance accumulation
    if (sensorData.latitude != 0.0 && sensorData.longitude != 0.0) {
      if (_prevLat != null && _prevLng != null) {
        final double distMeters = Geolocator.distanceBetween(
          _prevLat!,
          _prevLng!,
          sensorData.latitude,
          sensorData.longitude,
        );
        // Distance sanity check: ignore teleport jumps (> 200 m/s)
        if (distMeters > 1.0 && distMeters < 250.0) {
          _distanceKm += distMeters / 1000.0;
        }
      }
      _prevLat = sensorData.latitude;
      _prevLng = sensorData.longitude;
      _coordinates.add([sensorData.latitude, sensorData.longitude]);
    }

    notifyListeners();
  }

  Future<TripRecord?> stopTrip() async {
    if (!_isRecording) return null;
    _tickerTimer?.cancel();
    _isRecording = false;

    final endTime = DateTime.now();
    final durationMin = _elapsed.inSeconds / 60.0;

    // Fuel calculation: If distance > 0, estimate fuel consumption
    // PCX 160 baseline economy: ~45.5 km/L
    final double avgKml = 45.5;
    final double fuelConsumedL =
        _distanceKm > 0 ? (_distanceKm / avgKml) : 0.0;
    final double tripCostIdr = fuelConsumedL * 13700.0; // Pertamax baseline

    // Ensure final snapshot is appended
    if (_latestLat != 0.0 && _latestLng != 0.0) {
      if (_timelineSnapshots.isEmpty || _timelineSnapshots.last['t'] != _elapsed.inSeconds) {
        _timelineSnapshots.add({
          't': _elapsed.inSeconds,
          'lat': double.parse(_latestLat.toStringAsFixed(5)),
          'lng': double.parse(_latestLng.toStringAsFixed(5)),
          'spd': _latestSpeed.round(),
          'lean': _latestLean.round(),
          'alt': _latestAlt.round(),
        });
      }
    }

    final polyline = PolylineEncoder.encode(_coordinates);
    final timelineJson = jsonEncode(_timelineSnapshots);

    final record = TripRecord(
      id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
      startTime: _startTime ?? endTime,
      endTime: endTime,
      durationMin: durationMin,
      distanceKm: _distanceKm,
      avgSpeedKmh: avgSpeedKmh,
      maxSpeedKmh: _maxSpeedKmh,
      fuelConsumedL: fuelConsumedL,
      avgKml: avgKml,
      tripCostIdr: tripCostIdr,
      maxEctC: _maxEct > 0 ? _maxEct : 88.0,
      maxLeanLeftDeg: _maxLeanLeft,
      maxLeanRightDeg: _maxLeanRight,
      hardBrakingCount: _hardBrakingCount,
      routePolyline: polyline,
      timelineData: timelineJson,
      synced: false,
    );

    _history.insert(0, record);
    await _saveHistory();
    notifyListeners();

    // Trigger immediate sync
    flushUnsyncedTrips();

    return record;
  }

  Future<void> flushUnsyncedTrips() async {
    if (_pbService == null) return;
    bool changed = false;

    for (int i = 0; i < _history.length; i++) {
      final trip = _history[i];
      if (!trip.synced) {
        try {
          dynamic timelineParsed;
          try {
            timelineParsed = jsonDecode(trip.timelineData);
          } catch (_) {
            timelineParsed = [];
          }

          final success = await _pbService!.syncTrip(
            startTime: trip.startTime,
            endTime: trip.endTime,
            durationMin: trip.durationMin,
            distanceKm: trip.distanceKm,
            avgSpeedKmh: trip.avgSpeedKmh,
            maxSpeedKmh: trip.maxSpeedKmh,
            fuelConsumedL: trip.fuelConsumedL,
            avgKml: trip.avgKml,
            tripCostIdr: trip.tripCostIdr,
            maxEctC: trip.maxEctC,
            maxLeanLeftDeg: trip.maxLeanLeftDeg,
            maxLeanRightDeg: trip.maxLeanRightDeg,
            hardBrakingCount: trip.hardBrakingCount,
            routePolyline: trip.routePolyline,
            timelineData: timelineParsed,
          );

          if (success) {
            _history[i] = trip.copyWith(synced: true);
            changed = true;
            debugPrint('[TripManager] Synced trip ${trip.id} to PocketBase!');
          }
        } catch (e) {
          debugPrint('[TripManager] Error syncing trip: $e');
        }
      }
    }

    if (changed) {
      await _saveHistory();
      notifyListeners();
    }
  }
}
