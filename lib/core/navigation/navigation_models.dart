import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class NavPlace {
  final String name;
  final String detail;
  final double lat;
  final double lng;

  const NavPlace({
    required this.name,
    required this.detail,
    required this.lat,
    required this.lng,
  });

  LatLng get toLatLng => LatLng(lat, lng);
}

enum ManeuverType {
  depart,
  turn,
  roundabout,
  uturn,
  fork,
  arrive,
  unknown,
}

class NavStep {
  final String instruction;
  final String streetName;
  final double distanceMeters;
  final double durationSec;
  final ManeuverType type;
  final String modifier; // left, right, slight left, etc.
  final LatLng location;

  const NavStep({
    required this.instruction,
    required this.streetName,
    required this.distanceMeters,
    required this.durationSec,
    required this.type,
    required this.modifier,
    required this.location,
  });

  IconData get icon {
    switch (type) {
      case ManeuverType.arrive:
        return Icons.flag;
      case ManeuverType.uturn:
        return Icons.u_turn_left;
      case ManeuverType.roundabout:
        return Icons.roundabout_left;
      case ManeuverType.turn:
      case ManeuverType.fork:
        if (modifier.contains('left')) {
          if (modifier.contains('slight')) return Icons.turn_slight_left;
          if (modifier.contains('sharp')) return Icons.turn_sharp_left;
          return Icons.turn_left;
        } else if (modifier.contains('right')) {
          if (modifier.contains('slight')) return Icons.turn_slight_right;
          if (modifier.contains('sharp')) return Icons.turn_sharp_right;
          return Icons.turn_right;
        }
        return Icons.straight;
      case ManeuverType.depart:
      default:
        return Icons.navigation;
    }
  }
}

class NavRoute {
  final double totalDistanceMeters;
  final double totalDurationSec;
  final List<LatLng> polyline;
  final List<NavStep> steps;

  const NavRoute({
    required this.totalDistanceMeters,
    required this.totalDurationSec,
    required this.polyline,
    required this.steps,
  });
}
