import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../logger/app_logger.dart';

class PocketBaseService {
  late PocketBase pb;
  String? currentVehicleId;

  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);
  bool get isAuthenticated => pb.authStore.isValid && isConnectedNotifier.value;
  String? get currentUserId => pb.authStore.model?.id;

  PocketBaseService({String? baseUrl}) {
    pb = PocketBase(baseUrl ?? ApiConstants.defaultBaseUrl);
  }

  Future<bool> autoLogin() async {
    final hosts = [
      ApiConstants.defaultBaseUrl,
      ApiConstants.lanBaseUrl,
      ApiConstants.tailscaleBaseUrl,
    ];

    for (final host in hosts) {
      try {
        pb = PocketBase(host);
        final success = await login(
          ApiConstants.defaultUserEmail,
          ApiConstants.defaultUserPass,
        );
        if (success) {
          isConnectedNotifier.value = true;
          debugPrint('[PBService] Successfully connected to host: $host');
          return true;
        }
      } catch (e) {
        debugPrint('[PBService] Failed connecting to $host: $e');
      }
    }

    isConnectedNotifier.value = false;
    return false;
  }

  Future<bool> login(String email, String password) async {
    try {
      final authData =
          await pb.collection('users').authWithPassword(email, password);
      AppLogger().initialize(pb: pb, userId: authData.record.id);

      // Cache token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pb_token', pb.authStore.token);
      await prefs.setString('pb_user_id', authData.record.id);

      // Load or create default PCX 160 vehicle record
      await _ensureVehicleExists();
      isConnectedNotifier.value = true;
      return true;
    } catch (e) {
      debugPrint('[PBService] Login error: $e');
      isConnectedNotifier.value = false;
      return false;
    }
  }

  Future<void> _ensureVehicleExists() async {
    try {
      final list = await pb.collection(ApiConstants.collectionVehicles).getList(
            page: 1,
            perPage: 1,
            filter: 'user = "$currentUserId"',
          );

      if (list.items.isNotEmpty) {
        currentVehicleId = list.items.first.id;
      } else {
        final newVehicle =
            await pb.collection(ApiConstants.collectionVehicles).create(
          body: {
            'user': currentUserId,
            'name': 'Honda PCX 160 eSP+ ABS',
            'plate_number': 'B 1234 SC',
            'tank_capacity_l': ApiConstants.pcxTankCapacityL,
            'fuel_type': 'Pertamax 92',
            'fuel_price_per_l': ApiConstants.defaultFuelPriceIdr,
            'current_fuel_level_l': 6.5,
            'engine_cc': 156.9,
            've_factor': ApiConstants.pcxVolumetricEfficiency,
            'odometer_km': 0.0,
            'total_engine_hours': 0.0,
          },
        );
        currentVehicleId = newVehicle.id;
      }
    } catch (e) {
      debugPrint('[PBService] Vehicle check error: $e');
    }
  }

  Future<bool> syncPreRideScan({
    required double batteryStandbyV,
    required double batteryCrankingV,
    required String batteryHealth,
    required List<dynamic> dtcCodes,
    required double ambientTempC,
    required bool allClear,
  }) async {
    if (!isAuthenticated || currentVehicleId == null) {
      await autoLogin();
    }
    if (!isAuthenticated || currentVehicleId == null) return false;

    try {
      await pb.collection(ApiConstants.collectionPreRideScans).create(
        body: {
          'user': currentUserId,
          'vehicle': currentVehicleId,
          'timestamp': DateTime.now().toIso8601String(),
          'battery_standby_v': batteryStandbyV,
          'battery_cranking_v': batteryCrankingV,
          'battery_health': batteryHealth,
          'dtc_codes': dtcCodes,
          'ambient_temp_c': ambientTempC,
          'all_clear': allClear,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[PBService] Sync PreRide error: $e');
      return false;
    }
  }

  Future<bool> syncTrip({
    required DateTime startTime,
    required DateTime endTime,
    required double durationMin,
    required double distanceKm,
    required double avgSpeedKmh,
    required double maxSpeedKmh,
    required double fuelConsumedL,
    required double avgKml,
    required double tripCostIdr,
    required double maxEctC,
    required double maxLeanLeftDeg,
    required double maxLeanRightDeg,
    required int hardBrakingCount,
    required String routePolyline,
    dynamic timelineData,
  }) async {
    // Auto-authenticate & ensure vehicle exists if not ready
    if (!isAuthenticated || currentVehicleId == null) {
      await autoLogin();
    }
    if (!isAuthenticated || currentVehicleId == null) return false;

    try {
      await pb.collection(ApiConstants.collectionTrips).create(
        body: {
          'user': currentUserId,
          'vehicle': currentVehicleId,
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'duration_min': durationMin,
          'distance_km': distanceKm,
          'avg_speed_kmh': avgSpeedKmh,
          'max_speed_kmh': maxSpeedKmh,
          'fuel_consumed_l': fuelConsumedL,
          'avg_kml': avgKml,
          'trip_cost_idr': tripCostIdr,
          'max_ect_c': maxEctC,
          'max_lean_left_deg': maxLeanLeftDeg,
          'max_lean_right_deg': maxLeanRightDeg,
          'hard_braking_count': hardBrakingCount,
          'route_polyline': routePolyline,
          if (timelineData != null) 'timeline_data': timelineData,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[PBService] Sync Trip error: $e');
      return false;
    }
  }

  Future<bool> syncMaintenanceRecord({
    required String component,
    required double lastServiceKm,
    required double nextServiceKm,
    required String status,
  }) async {
    if (!isAuthenticated || currentVehicleId == null) {
      await autoLogin();
    }
    if (!isAuthenticated || currentVehicleId == null) return false;

    try {
      await pb.collection(ApiConstants.collectionMaintenance).create(
        body: {
          'user': currentUserId,
          'vehicle': currentVehicleId,
          'component': component,
          'last_service_km': lastServiceKm,
          'next_service_km': nextServiceKm,
          'status': status,
        },
      );
      return true;
    } catch (e) {
      debugPrint('[PBService] Sync Maintenance error: $e');
      return false;
    }
  }
}
