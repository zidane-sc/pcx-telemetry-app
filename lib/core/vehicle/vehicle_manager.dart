import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vehicle_profile.dart';

class VehicleManager extends ChangeNotifier {
  static final VehicleManager _instance = VehicleManager._internal();
  factory VehicleManager() => _instance;
  VehicleManager._internal();

  final List<VehicleProfile> _vehicles = [];
  String _activeVehicleId = VehicleProfile.defaultPcx160.id;

  List<VehicleProfile> get vehicles => List.unmodifiable(_vehicles);

  VehicleProfile get activeVehicle {
    return _vehicles.firstWhere(
      (v) => v.id == _activeVehicleId,
      orElse: () => _vehicles.isNotEmpty
          ? _vehicles.first
          : VehicleProfile.defaultPcx160,
    );
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getString('saved_vehicle_profiles');
      final savedActiveId = prefs.getString('active_vehicle_id');

      _vehicles.clear();
      if (rawList != null && rawList.isNotEmpty) {
        final decoded = jsonDecode(rawList) as List<dynamic>;
        for (final item in decoded) {
          _vehicles.add(VehicleProfile.fromJson(item as Map<String, dynamic>));
        }
      }

      if (_vehicles.isEmpty) {
        _vehicles.add(VehicleProfile.defaultPcx160);
        _vehicles.add(VehicleProfile.defaultYaris2014);
        await _save();
      }

      if (savedActiveId != null &&
          _vehicles.any((v) => v.id == savedActiveId)) {
        _activeVehicleId = savedActiveId;
      } else {
        _activeVehicleId = _vehicles.first.id;
      }
    } catch (e) {
      debugPrint('[VehicleManager] Init error: $e');
    }
    notifyListeners();
  }

  Future<void> selectVehicle(String id) async {
    if (_activeVehicleId == id) return;
    _activeVehicleId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_vehicle_id', id);
    notifyListeners();
  }

  Future<void> saveVehicle(VehicleProfile profile) async {
    final idx = _vehicles.indexWhere((v) => v.id == profile.id);
    if (idx >= 0) {
      _vehicles[idx] = profile;
    } else {
      _vehicles.add(profile);
    }
    await _save();
    notifyListeners();
  }

  Future<void> deleteVehicle(String id) async {
    if (_vehicles.length <= 1) return; // Keep at least one
    _vehicles.removeWhere((v) => v.id == id);
    if (_activeVehicleId == id) {
      _activeVehicleId = _vehicles.first.id;
    }
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_vehicles.map((v) => v.toJson()).toList());
      await prefs.setString('saved_vehicle_profiles', raw);
      await prefs.setString('active_vehicle_id', _activeVehicleId);
    } catch (_) {}
  }
}
