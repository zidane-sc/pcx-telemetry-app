import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/telemetry/ride_report_service.dart';
import 'package:pcx_telemetry_app/core/trip/trip_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

TripRecord trip(String id) => TripRecord.fromJson({
      'id': id,
      'startTime': '2026-01-0${id.codeUnitAt(0) % 9 + 1}T01:00:00.000Z',
      'endTime': '2026-01-01T01:42:00.000Z',
      'durationMin': 42.0,
      'distanceKm': 18.4,
      'avgSpeedKmh': 26.3,
      'maxSpeedKmh': 74.0,
      'fuelConsumedL': 3.2,
      'avgKml': 57.5,
      'tripCostIdr': 41440,
      'maxEctC': 94.0,
      'maxLeanLeftDeg': 41.0,
      'maxLeanRightDeg': 44.5,
      'hardBrakingCount': 2,
      'routePolyline': 'abc',
      'timelineData': '[]',
      'synced': false,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.zidane.pcx_telemetry_app/actions');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getCacheDir':
          return Directory.systemTemp.createTempSync('pcx_test').path;
        case 'shareFile':
          return true;
        case 'smsDraft':
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('RideReportService — share', () {
    test('writes a real PDF to the cache and invokes the share sheet', () async {
      final svc = RideReportService();
      final ok = await svc.shareReport(trip('1'));

      expect(ok, isTrue);
      expect(calls.map((c) => c.method), containsAll(['getCacheDir', 'shareFile']));

      final share = calls.firstWhere((c) => c.method == 'shareFile');
      final args = share.arguments as Map<Object?, Object?>;
      final path = args['path'] as String;
      expect(args['mime'], 'application/pdf');
      expect(path, endsWith('.pdf'));

      final f = File(path);
      expect(f.existsSync(), isTrue);
      final bytes = f.readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    });

    test('returns false when the native share throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'shareFile') {
          throw PlatformException(code: 'no_activity');
        }
        return Directory.systemTemp.createTempSync('pcx_test').path;
      });

      final ok = await RideReportService().shareReport(trip('1'));
      expect(ok, isFalse,
          reason: 'the caller must see a real failure, not a silent success');
    });

    test('returns false when the native share reports refusal', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'shareFile') return false;
        return Directory.systemTemp.createTempSync('pcx_test').path;
      });
      expect(await RideReportService().shareReport(trip('1')), isFalse);
    });

    test('the report filename carries the trip timestamp', () async {
      await RideReportService().shareReport(trip('1'));
      final share = calls.firstWhere((c) => c.method == 'shareFile');
      final path = (share.arguments as Map<Object?, Object?>)['path'] as String;
      expect(path, contains('ride-'));
      expect(path, isNot(contains(':')),
          reason: 'colons are stripped; they break Windows and some shares');
    });

    test('a sparse trip still produces a valid file', () async {
      final sparse = TripRecord.fromJson({
        'id': 'x',
        'startTime': '2026-01-01T01:00:00.000Z',
        'endTime': '2026-01-01T01:05:00.000Z',
        'durationMin': 5.0,
        'distanceKm': 0.0,
        'avgSpeedKmh': 0.0,
        'maxSpeedKmh': 0.0,
        'fuelConsumedL': 0.0,
        'avgKml': 0.0,
        'tripCostIdr': 0.0,
        'maxEctC': 0.0,
        'maxLeanLeftDeg': 0.0,
        'maxLeanRightDeg': 0.0,
        'hardBrakingCount': 0,
        'routePolyline': '',
        'timelineData': '[]',
        'synced': false,
      });
      expect(await RideReportService().shareReport(sparse), isTrue);
    });
  });

  group('RideReportService — emergency contact', () {
    test('strips anything that is not a dialable character', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = RideReportService();
      await svc.setEmergencyContact('+62 812-3456-7890');
      // Dashes are removed rather than converted to spaces: the SMS app
      // accepts either, and dropping the separator is the smaller change.
      expect(svc.emergencyContact, '+62 81234567890');
      expect(svc.emergencyContact, isNot(contains('-')));
    });

    test('strips letters and symbols that would corrupt the URI', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = RideReportService();
      await svc.setEmergencyContact('0812<script>3456#789');
      // Spaces are stripped too: a bare digit string is what the SMS app
      // wants, and it avoids encoding quirks in the smsto: URI.
      expect(svc.emergencyContact, '08123456789');
      expect(svc.emergencyContact, isNot(contains('<')));
      expect(svc.emergencyContact, isNot(contains('#')));
    });

    test('persists and reloads the contact', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = RideReportService();
      await svc.setEmergencyContact('08123456789');

      // A fresh instance reading the same store sees the number.
      final reloaded = RideReportService();
      await reloaded.init();
      expect(reloaded.emergencyContact, '08123456789');
    });

    test('smsDraft is refused when no contact is set', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = RideReportService();
      await svc.init();
      final ok = await svc.openEmergencySms('crash');
      expect(ok, isFalse);
      expect(calls.where((c) => c.method == 'smsDraft'), isEmpty);
    });

    test('smsDraft opens a composer, never a send', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = RideReportService();
      await svc.setEmergencyContact('08123456789');

      final ok = await svc.openEmergencySms('SayaZT, terjadi kecelakaan');
      expect(ok, isTrue);

      final call = calls.firstWhere((c) => c.method == 'smsDraft');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['number'], '08123456789');
      expect(args['body'], contains('kecelakaan'));
      expect(calls.map((c) => c.method), isNot(contains('sendSms')),
          reason: 'there is no send path in this app at all');
    });
  });
}