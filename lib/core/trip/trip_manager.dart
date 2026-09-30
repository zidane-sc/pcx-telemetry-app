import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sensors/sensor_hub.dart';
import '../models/telemetry_data.dart';
import '../sync/pocketbase_service.dart';
import 'polyline_encoder.dart';

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
    required this.synced,
  });

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

  double? _prevLat;
  double? _prevLng;
  final List<List<double>> _coordinates = [];
  final List<TripRecord> _history = [];
  List<TripRecord> get history => List.unmodifiable(_history);

  Future<void> init({required PocketBaseService pbService}) async {
    _pbService = pbService;
    await _loadHistory();
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

    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startTime != null) {
        _elapsed = DateTime.now().difference(_startTime!);
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

    // Speed: prefer OBD if available & running, else GPS satellite speed
    final double speed = (obdFrame != null && obdFrame.speedKmh > 1.0)
        ? obdFrame.speedKmh
        : sensorData.gpsSpeedKmh;

    if (speed > _maxSpeedKmh) _maxSpeedKmh = speed;
    _speedSum += speed;
    _speedSamples++;

    // Lean Angle from smartphone IMU Gyro
    final double roll = sensorData.rollAngleDeg;
    if (roll < -_maxLeanLeft) _maxLeanLeft = -roll;
    if (roll > _maxLeanRight) _maxLeanRight = roll;

    // Hard Braking detection (G-force < -0.45 G)
    if (sensorData.gForce < -0.45) {
      _hardBrakingCount++;
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
        // Sanity check to avoid GPS teleport glitches (> 200 m/s)
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

    final polyline = PolylineEncoder.encode(_coordinates);

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
      synced: false,
    );

    _history.insert(0, record);
    await _saveHistory();
    notifyListeners();

    // Auto-sync to PocketBase in background
    _syncToPocketBase(record);

    return record;
  }

  Future<void> _syncToPocketBase(TripRecord record) async {
    if (_pbService == null) return;
    try {
      final success = await _pbService!.syncTrip(
        startTime: record.startTime,
        endTime: record.endTime,
        durationMin: record.durationMin,
        distanceKm: record.distanceKm,
        avgSpeedKmh: record.avgSpeedKmh,
        maxSpeedKmh: record.maxSpeedKmh,
        fuelConsumedL: record.fuelConsumedL,
        avgKml: record.avgKml,
        tripCostIdr: record.tripCostIdr,
        maxEctC: record.maxEctC,
        maxLeanLeftDeg: record.maxLeanLeftDeg,
        maxLeanRightDeg: record.maxLeanRightDeg,
        hardBrakingCount: record.hardBrakingCount,
        routePolyline: record.routePolyline,
      );
      if (success) {
        debugPrint('[TripManager] Trip successfully synced to PocketBase!');
      }
    } catch (e) {
      debugPrint('[TripManager] Sync to PocketBase failed: $e');
    }
  }
}
