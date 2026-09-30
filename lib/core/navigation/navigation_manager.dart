import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../audio/voice_alert_service.dart';
import 'navigation_models.dart';
import 'routing_service.dart';

class NavigationManager extends ChangeNotifier {
  static final NavigationManager _instance = NavigationManager._internal();
  factory NavigationManager() => _instance;
  NavigationManager._internal();

  bool _isNavigating = false;
  bool get isNavigating => _isNavigating;

  NavRoute? _currentRoute;
  NavRoute? get currentRoute => _currentRoute;

  NavPlace? _destination;
  NavPlace? get destination => _destination;

  int _currentStepIndex = 0;
  int get currentStepIndex => _currentStepIndex;

  double _distanceToNextStepMeters = 0.0;
  double get distanceToNextStepMeters => _distanceToNextStepMeters;

  double _totalRemainingDistanceMeters = 0.0;
  double get totalRemainingDistanceMeters => _totalRemainingDistanceMeters;

  NavStep? get currentStep {
    if (_currentRoute == null || _currentRoute!.steps.isEmpty) return null;
    if (_currentStepIndex >= _currentRoute!.steps.length) {
      return _currentRoute!.steps.last;
    }
    return _currentRoute!.steps[_currentStepIndex];
  }

  // Voice prompting debounces
  int? _lastPromptedStepIndex;
  bool _prompted200m = false;
  bool _prompted50m = false;

  // Off-route reroute guard
  DateTime? _lastRerouteTime;
  bool _isRerouting = false;

  void startNavigation(NavRoute route, NavPlace dest) {
    _currentRoute = route;
    _destination = dest;
    _currentStepIndex = 0;
    _distanceToNextStepMeters = 0.0;
    _totalRemainingDistanceMeters = route.totalDistanceMeters;
    _isNavigating = true;
    _lastPromptedStepIndex = null;
    _prompted200m = false;
    _prompted50m = false;

    VoiceAlertService().speakAlert(
      "Rute dimulai. ${route.steps.isNotEmpty ? route.steps.first.instruction : 'Ikuti jalur peta.'}",
    );

    notifyListeners();
  }

  void stopNavigation() {
    if (!_isNavigating) return;
    _isNavigating = false;
    _currentRoute = null;
    _destination = null;
    _currentStepIndex = 0;
    _distanceToNextStepMeters = 0.0;
    _totalRemainingDistanceMeters = 0.0;

    VoiceAlertService().speakAlert("Navigasi dihentikan.");
    notifyListeners();
  }

  void updateLocation({
    required double lat,
    required double lng,
    required double speedKmh,
  }) {
    if (!_isNavigating || _currentRoute == null || _currentRoute!.steps.isEmpty) {
      return;
    }

    final currentPos = LatLng(lat, lng);
    final step = currentStep;
    if (step == null) return;

    // Calculate distance to current step's maneuver point
    final dist = Geolocator.distanceBetween(
      currentPos.latitude,
      currentPos.longitude,
      step.location.latitude,
      step.location.longitude,
    );

    _distanceToNextStepMeters = dist;

    // Reset prompt flags when advancing to a new step
    if (_lastPromptedStepIndex != _currentStepIndex) {
      _lastPromptedStepIndex = _currentStepIndex;
      _prompted200m = false;
      _prompted50m = false;
    }

    // Voice alert prompts
    if (dist <= 250.0 && dist > 80.0 && !_prompted200m) {
      _prompted200m = true;
      VoiceAlertService().speakAlert(
        "200 meter lagi, ${step.instruction}",
      );
    } else if (dist <= 50.0 && dist > 15.0 && !_prompted50m) {
      _prompted50m = true;
      VoiceAlertService().speakAlert(step.instruction);
    }

    // Turn completed threshold: within 25 meters of maneuver point
    if (dist <= 28.0) {
      if (_currentStepIndex < _currentRoute!.steps.length - 1) {
        _currentStepIndex++;
        final next = currentStep!;
        VoiceAlertService().speakAlert(next.instruction);
      } else {
        // Arrived at destination
        VoiceAlertService().speakAlert("Anda telah tiba di tujuan.");
        stopNavigation();
        return;
      }
    }

    // Off-route detection: check distance to nearest point along the polyline
    _checkOffRouteAndReroute(currentPos);

    notifyListeners();
  }

  void _checkOffRouteAndReroute(LatLng currentPos) async {
    if (_isRerouting || _currentRoute == null || _destination == null) return;
    final now = DateTime.now();
    if (_lastRerouteTime != null &&
        now.difference(_lastRerouteTime!).inSeconds < 15) {
      return; // Cooldown 15s between reroutes
    }

    // Find minimum distance to any point in the polyline
    double minPolyDist = double.infinity;
    for (final pt in _currentRoute!.polyline) {
      final d = Geolocator.distanceBetween(
        currentPos.latitude,
        currentPos.longitude,
        pt.latitude,
        pt.longitude,
      );
      if (d < minPolyDist) minPolyDist = d;
      if (minPolyDist < 30.0) break; // Still on route
    }

    // If rider drifted more than 65 meters away from the route
    if (minPolyDist > 65.0) {
      _isRerouting = true;
      _lastRerouteTime = now;
      VoiceAlertService().speakAlert("Menghitung ulang rute...");

      final newRoute = await RoutingService.calculateRoute(
        origin: currentPos,
        destination: _destination!.toLatLng,
      );

      _isRerouting = false;
      if (newRoute != null && _isNavigating) {
        _currentRoute = newRoute;
        _currentStepIndex = 0;
        _prompted200m = false;
        _prompted50m = false;
        VoiceAlertService().speakAlert(
          "Rute baru ditemukan. ${newRoute.steps.isNotEmpty ? newRoute.steps.first.instruction : ''}",
        );
        notifyListeners();
      }
    }
  }
}
