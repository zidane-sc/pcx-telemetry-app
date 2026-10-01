import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../trip/trip_manager.dart';
import 'ride_report_pdf.dart';

/// Writes the ride report PDF and hands it to the Android share sheet.
///
/// Native calls go through a MethodChannel rather than the `share_plus` or
/// `url_launcher` packages: this app already owns a MainActivity MethodChannel
/// for TTS, so adding a second channel there costs ~40 lines of Kotlin and
/// zero APK weight, where either package adds a plugin plus its own channel.
class RideReportService {
  static final RideReportService _instance = RideReportService._internal();
  factory RideReportService() => _instance;
  RideReportService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.zidane.pcx_telemetry_app/actions');

  static const String _emergencyContactKey = 'emergency_contact_number';
  static const String _cacheSubdir = 'ride_reports';

  String get emergencyContact =>
      _emergencyContact ?? '';

  String? _emergencyContact;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _emergencyContact = prefs.getString(_emergencyContactKey) ?? '';
    } catch (_) {}
  }

  Future<void> setEmergencyContact(String number) async {
    // Digits, spaces and a leading + only. Anything else would either be
    // rejected by the SMS app or, worse, be treated as a URI fragment.
    final cleaned = number.replaceAll(RegExp(r'[^0-9+\s]'), '');
    _emergencyContact = cleaned;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_emergencyContactKey, cleaned);
    } catch (_) {}
  }

  /// Renders the report and opens the Android share sheet.
  ///
  /// Returns false when the file could not be written or the share sheet could
  /// not be opened, so the caller can show a real error instead of pretending
  /// the report was shared.
  Future<bool> shareReport(TripRecord trip) async {
    final bytes = buildRideReportPdf(trip);

    try {
      final dir = Directory('${await getCacheDir()}/$_cacheSubdir');
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      // Old reports accumulate in the cache dir. Keep the newest few so a
      // rider who shares daily does not fill the phone.
      _pruneOldReports(dir);

      final stamp = trip.startTime
          .toLocal()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}/ride-$stamp.pdf');
      await file.writeAsBytes(bytes, flush: true);

      return await _channel.invokeMethod<bool>('shareFile', {
            'path': file.path,
            'mime': 'application/pdf',
            'subject':
                'Ride Report ${trip.startTime.toLocal().toString().split('.').first}',
          }) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[RideReport] share failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[RideReport] build/write failed: $e');
      return false;
    }
  }

  /// Opens an SMS composer pre-filled for the emergency contact.
  ///
  /// This never sends: the composer is left for the rider to confirm. An
  /// automatic send on the crash path would message someone from a moving
  /// motorcycle on a false positive.
  Future<bool> openEmergencySms(String message) async {
    final contact = emergencyContact;
    if (contact.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('smsDraft', {
            'number': contact,
            'body': message,
          }) ??
          false;
    } catch (e) {
      debugPrint('[RideReport] sms failed: $e');
      return false;
    }
  }

  void _pruneOldReports(Directory dir) {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'))
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final old in files.skip(5)) {
        old.deleteSync();
      }
    } catch (_) {
      // Pruning is housekeeping; a failure must not block the share.
    }
  }
}

/// Returns the app's cache directory.
///
/// `Directory.systemTemp` is /tmp on the build host, which does not exist in an
/// Android app sandbox — writing there throws. The real cache dir comes from
/// the native side (`context.cacheDir`), which is exactly the path declared
/// in `res/xml/file_paths.xml`.
Future<String> getCacheDir() async {
  final path = await RideReportService._channel
      .invokeMethod<String>('getCacheDir');
  if (path != null && path.isNotEmpty) return path;
  // Host-side fallback so the pure-Dart tests can run off-device.
  return Directory.systemTemp.path;
}