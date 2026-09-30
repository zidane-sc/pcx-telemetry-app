import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'navigation_models.dart';

class RoutingService {
  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  /// Search places via Photon API (OpenStreetMap geocoding by Komoot)
  static Future<List<NavPlace>> searchPlaces(
    String query, {
    double? userLat,
    double? userLng,
  }) async {
    if (query.trim().isEmpty) return [];

    try {
      final encodedQuery = Uri.encodeComponent(query.trim());
      String urlStr = 'https://photon.komoot.io/api/?q=$encodedQuery&limit=8';

      // Prioritize locations near current user position
      if (userLat != null && userLng != null) {
        urlStr += '&lat=$userLat&lon=$userLng';
      }

      final uri = Uri.parse(urlStr);
      final request = await _client.getUrl(uri);
      request.headers.set('User-Agent', 'PcxTelemetryApp/1.0');
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final features = json['features'] as List<dynamic>? ?? [];

        final results = <NavPlace>[];
        for (final f in features) {
          final props = f['properties'] as Map<String, dynamic>? ?? {};
          final geom = f['geometry'] as Map<String, dynamic>? ?? {};
          final coords = geom['coordinates'] as List<dynamic>? ?? [];

          if (coords.length >= 2) {
            final lng = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();

            final name = props['name']?.toString() ??
                props['street']?.toString() ??
                query;

            final List<String> details = [];
            if (props['street'] != null && props['street'] != name) {
              details.add(props['street'].toString());
            }
            if (props['city'] != null) details.add(props['city'].toString());
            if (props['state'] != null) details.add(props['state'].toString());
            if (props['country'] != null) {
              details.add(props['country'].toString());
            }

            results.add(
              NavPlace(
                name: name,
                detail: details.isNotEmpty ? details.join(', ') : 'Indonesia',
                lat: lat,
                lng: lng,
              ),
            );
          }
        }
        return results;
      }
    } catch (e) {
      debugPrint('[RoutingService] Photon search error: $e');
    }
    return [];
  }

  /// Calculate route using public OSRM API with full turn maneuvers & steps
  static Future<NavRoute?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final urlStr =
          'https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&steps=true';

      final uri = Uri.parse(urlStr);
      final request = await _client.getUrl(uri);
      request.headers.set('User-Agent', 'PcxTelemetryApp/1.0');
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final routes = json['routes'] as List<dynamic>? ?? [];

        if (routes.isNotEmpty) {
          final r = routes[0] as Map<String, dynamic>;
          final double distance = (r['distance'] as num?)?.toDouble() ?? 0.0;
          final double duration = (r['duration'] as num?)?.toDouble() ?? 0.0;

          // Decode GeoJSON coordinates
          final geom = r['geometry'] as Map<String, dynamic>? ?? {};
          final rawCoords = geom['coordinates'] as List<dynamic>? ?? [];
          final polyline = <LatLng>[];
          for (final c in rawCoords) {
            if (c is List && c.length >= 2) {
              polyline.add(LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ));
            }
          }

          // Decode turn-by-turn steps
          final steps = <NavStep>[];
          final legs = r['legs'] as List<dynamic>? ?? [];
          if (legs.isNotEmpty) {
            final rawSteps = legs[0]['steps'] as List<dynamic>? ?? [];
            for (final s in rawSteps) {
              final maneuver = s['maneuver'] as Map<String, dynamic>? ?? {};
              final mTypeStr = maneuver['type']?.toString().toLowerCase() ?? '';
              final mModStr =
                  maneuver['modifier']?.toString().toLowerCase() ?? '';
              final mLoc = maneuver['location'] as List<dynamic>? ?? [];

              LatLng loc = origin;
              if (mLoc.length >= 2) {
                loc = LatLng(
                    (mLoc[1] as num).toDouble(), (mLoc[0] as num).toDouble());
              }

              ManeuverType type = ManeuverType.turn;
              if (mTypeStr == 'depart') {
                type = ManeuverType.depart;
              } else if (mTypeStr == 'arrive') {
                type = ManeuverType.arrive;
              } else if (mTypeStr == 'roundabout' || mTypeStr == 'rotary') {
                type = ManeuverType.roundabout;
              } else if (mModStr.contains('uturn')) {
                type = ManeuverType.uturn;
              } else if (mTypeStr == 'fork') {
                type = ManeuverType.fork;
              }

              final streetName = s['name']?.toString().trim() ?? '';
              String instruction = _buildHumanInstruction(type, mModStr, streetName);

              steps.add(NavStep(
                instruction: instruction,
                streetName: streetName.isNotEmpty ? streetName : 'Jalan Raya',
                distanceMeters: (s['distance'] as num?)?.toDouble() ?? 0.0,
                durationSec: (s['duration'] as num?)?.toDouble() ?? 0.0,
                type: type,
                modifier: mModStr,
                location: loc,
              ));
            }
          }

          return NavRoute(
            totalDistanceMeters: distance,
            totalDurationSec: duration,
            polyline: polyline,
            steps: steps,
          );
        }
      }
    } catch (e) {
      debugPrint('[RoutingService] Route calculation error: $e');
    }
    return null;
  }

  static String _buildHumanInstruction(
      ManeuverType type, String modifier, String street) {
    final streetLabel = street.isNotEmpty ? ' ke $street' : '';

    switch (type) {
      case ManeuverType.depart:
        return 'Mulai perjalanan$streetLabel';
      case ManeuverType.arrive:
        return 'Tiba di tujuan';
      case ManeuverType.uturn:
        return 'Putar balik$streetLabel';
      case ManeuverType.roundabout:
        return 'Masuk bundaran$streetLabel';
      case ManeuverType.fork:
        return modifier.contains('left')
            ? 'Ambil jalur kiri$streetLabel'
            : 'Ambil jalur kanan$streetLabel';
      case ManeuverType.turn:
      default:
        if (modifier.contains('left')) {
          if (modifier.contains('slight')) return 'Serong kiri$streetLabel';
          if (modifier.contains('sharp')) return 'Belok tajam ke kiri$streetLabel';
          return 'Belok kiri$streetLabel';
        } else if (modifier.contains('right')) {
          if (modifier.contains('slight')) return 'Serong kanan$streetLabel';
          if (modifier.contains('sharp')) return 'Belok tajam ke kanan$streetLabel';
          return 'Belok kanan$streetLabel';
        }
        return 'Lurus terus$streetLabel';
    }
  }
}
