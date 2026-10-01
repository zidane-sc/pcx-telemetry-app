import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'polyline_encoder.dart';
import 'trip_manager.dart';

class GpxExporter {
  /// Converts a TripRecord into standard GPX 1.1 XML format compatible with Strava, Relive, Google Earth
  static String generateGpx(TripRecord trip) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="PCX Cyber Telemetry" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">');
    buffer.writeln('  <metadata>');
    buffer.writeln('    <name>Trip ${trip.startTime.toIso8601String()}</name>');
    buffer.writeln('    <desc>Distance: ${trip.distanceKm.toStringAsFixed(2)} km, Max Speed: ${trip.maxSpeedKmh.toStringAsFixed(1)} km/h, Max Lean: L${trip.maxLeanLeftDeg.toStringAsFixed(0)} / R${trip.maxLeanRightDeg.toStringAsFixed(0)}</desc>');
    buffer.writeln('    <time>${trip.startTime.toUtc().toIso8601String()}</time>');
    buffer.writeln('  </metadata>');
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>PCX Telemetry - ${trip.distanceKm.toStringAsFixed(1)} KM</name>');
    buffer.writeln('    <type>motorcycle</type>');
    buffer.writeln('    <trkseg>');

    List<Map<String, dynamic>> points = [];
    try {
      final raw = jsonDecode(trip.timelineData) as List<dynamic>;
      points = raw.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {}

    if (points.isNotEmpty) {
      for (final p in points) {
        final lat = (p['lat'] as num?)?.toDouble() ?? 0.0;
        final lng = (p['lng'] as num?)?.toDouble() ?? 0.0;
        if (lat == 0.0 || lng == 0.0) continue;

        final alt = (p['alt'] as num?)?.toDouble() ?? 0.0;
        final spd = ((p['spd'] as num?)?.toDouble() ?? 0.0) / 3.6; // m/s
        final sec = (p['t'] as num?)?.toInt() ?? 0;
        final time = trip.startTime.add(Duration(seconds: sec)).toUtc().toIso8601String();

        buffer.writeln('      <trkpt lat="$lat" lon="$lng">');
        buffer.writeln('        <ele>$alt</ele>');
        buffer.writeln('        <time>$time</time>');
        buffer.writeln('        <extensions>');
        buffer.writeln('          <speed>${spd.toStringAsFixed(2)}</speed>');
        if (p.containsKey('lean')) {
          buffer.writeln('          <leanAngle>${p['lean']}</leanAngle>');
        }
        buffer.writeln('        </extensions>');
        buffer.writeln('      </trkpt>');
      }
    } else if (trip.routePolyline.isNotEmpty) {
      // Fallback: decode polyline if timeline snapshots were empty
      final decoded = PolylineEncoder.decode(trip.routePolyline);
      for (int i = 0; i < decoded.length; i++) {
        final pt = decoded[i];
        if (pt[0] == 0.0 && pt[1] == 0.0) continue;
        final time = trip.startTime.add(Duration(seconds: i * 2)).toUtc().toIso8601String();

        buffer.writeln('      <trkpt lat="${pt[0]}" lon="${pt[1]}">');
        buffer.writeln('        <time>$time</time>');
        buffer.writeln('      </trkpt>');
      }
    }

    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');

    return buffer.toString();
  }

  /// Exports GPX string to a file on local storage and returns absolute file path
  static Future<File> saveGpxToFile(TripRecord trip) async {
    final gpxContent = generateGpx(trip);
    final Directory dir = Directory('/sdcard/Download');
    final targetDir = await dir.exists() ? dir : Directory('${Directory.systemTemp.path}/gpx_exports');
    await targetDir.create(recursive: true);

    final filename = 'PCX_Trip_${trip.startTime.year}${trip.startTime.month.toString().padLeft(2, '0')}${trip.startTime.day.toString().padLeft(2, '0')}_${trip.startTime.hour.toString().padLeft(2, '0')}${trip.startTime.minute.toString().padLeft(2, '0')}.gpx';
    final file = File('${targetDir.path}/$filename');
    return await file.writeAsString(gpxContent);
  }
}
