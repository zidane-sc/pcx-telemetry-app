import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/trip/trip_manager.dart';

TripRecord base(Map<String, dynamic> overrides) => TripRecord.fromJson({
      'id': 't1',
      'startTime': '2026-01-01T08:00:00.000Z',
      'endTime': '2026-01-01T08:30:00.000Z',
      'durationMin': 30.0,
      'distanceKm': 12.5,
      'avgSpeedKmh': 25.0,
      'maxSpeedKmh': 62.0,
      'fuelConsumedL': 2.5,
      'avgKml': 50.0,
      'tripCostIdr': 32375,
      'maxEctC': 92.0,
      'maxLeanLeftDeg': 38.0,
      'maxLeanRightDeg': 41.0,
      'hardBrakingCount': 4,
      'routePolyline': 'abc',
      'timelineData': '[]',
      'synced': false,
      ...overrides,
    });

void main() {
  group('TripRecord engine-brake serialization', () {
    test('round-trips the three Sprint 3 fields', () {
      final t = base({
        'engineBrakingCount': 12,
        'serviceBrakingCount': 3,
        'engineBrakeSeconds': 41.5,
      });
      expect(t.engineBrakingCount, 12);
      expect(t.serviceBrakingCount, 3);
      expect(t.engineBrakeSeconds, 41.5);

      final back = TripRecord.fromJson(t.toJson());
      expect(back.engineBrakingCount, 12);
      expect(back.serviceBrakingCount, 3);
      expect(back.engineBrakeSeconds, 41.5);
    });

    test('a pre-Sprint-3 trip reads as zero, not as a crash', () {
      final t = base({});
      expect(t.engineBrakingCount, 0);
      expect(t.serviceBrakingCount, 0);
      expect(t.engineBrakeSeconds, 0.0);
    });

    test('tolerates a null or wrongly-typed value', () {
      final t = base({
        'engineBrakingCount': null,
        'serviceBrakingCount': 'lots',
        'engineBrakeSeconds': null,
      });
      expect(t.engineBrakingCount, 0);
      expect(t.serviceBrakingCount, 0);
      expect(t.engineBrakeSeconds, 0.0);
    });

    test('accepts an int where a double is expected', () {
      // jsonDecode can hand back int for a whole number. A `as double?` cast
      // would throw here and lose the whole trip record.
      final t = base({'engineBrakeSeconds': 42});
      expect(t.engineBrakeSeconds, 42.0);
    });

    test('copyWith preserves the new fields', () {
      final t = base({
        'engineBrakingCount': 7,
        'serviceBrakingCount': 2,
        'engineBrakeSeconds': 30.0,
      });
      final synced = t.copyWith(synced: true);
      expect(synced.engineBrakingCount, 7);
      expect(synced.serviceBrakingCount, 2);
      expect(synced.engineBrakeSeconds, 30.0);
      expect(synced.synced, isTrue);
    });
  });
}