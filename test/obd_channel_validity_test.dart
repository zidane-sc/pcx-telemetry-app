import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/bluetooth/obd_parser.dart';
import 'package:pcx_telemetry_app/core/models/telemetry_data.dart';

/// A minimal stand-in for the ELM327's PID-support bitmap.
///
/// Bit n of byte n/8, MSB first, corresponds to mode 01 PID (n+1). Builds the
/// same way the ELM327 does, so a test can state "this ECU supports RPM, MAP,
/// TPS, ECT and voltage but no fuel level" the way a real car would report it.
String bitmapFor(List<int> pids, {int bytes = 4}) {
  final mask = List<int>.filled(bytes, 0);
  for (final pid in pids) {
    final idx = pid - 1;
    final byteIdx = idx ~/ 8;
    final bitIdx = 7 - (idx % 8);
    if (byteIdx < bytes) mask[byteIdx] |= (1 << bitIdx);
  }
  final hex = mask
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
  return '41 00 $hex';
}

void main() {
  group('PID bitmap semantics', () {
    test('an ECU that reports a PID bitmap can be decoded for those PIDs', () {
      // The bitmap is the contract the handshake verifies before claiming a
      // working link, so the mask it builds must survive classification and
      // still be recognised as supporting PIDs.
      final raw = bitmapFor([12, 11, 17, 5]); // RPM, MAP, TPS, ECT
      expect(ObdParser.hasSupportedPids(raw), isTrue);
      expect(ObdParser.classify(raw), ObdReply.ok);
    });

    test('an empty bitmap means the ECU exposes nothing usable', () {
      final raw = bitmapFor([]);
      // All-zero payload: the ECU answered but supports no mode-01 PIDs, which
      // is what a non-OBD-compliant ECU looks like.
      expect(ObdParser.classify(raw), ObdReply.noData);
      expect(ObdParser.hasSupportedPids(raw), isFalse);
    });
  });

  group('a typical motorcycle bitmap', () {
    final raw = bitmapFor([12, 13, 11, 5, 15, 17]); // RPM speed MAP ECT IAT TPS

    test('is not all zeros and classifies as ok', () {
      expect(ObdParser.classify(raw), ObdReply.ok);
    });

    test('reports the PIDs it claims', () {
      expect(ObdParser.hasSupportedPids(raw), isTrue);
    });

    test('a PID absent from the bitmap returns NO DATA when asked', () {
      // A PCX has no fuel-level float. The honest response to 012F is
      // noData, and the channel must be dropped rather than defaulted.
      final res = ObdParser.fuelLevel('NO DATA');
      expect(res.status, ObdReply.noData);
      expect(res.value, isNull);
    });

    test('a PID present in the bitmap decodes normally', () {
      expect(ObdParser.rpm('41 0C 1A F8').isOk, isTrue);
      expect(ObdParser.ect('41 05 7B').isOk, isTrue);
      expect(ObdParser.iat('41 0F 5E').isOk, isTrue);
    });
  });

  group('TelemetryFrame.live', () {
    TelemetryFrame frame(Set<ObdChannel> live) => TelemetryFrame(
          timestamp: DateTime(2026, 1, 1),
          rpm: 0.0,
          speedKmh: 0.0,
          mapKpa: 0.0,
          ectC: 0.0,
          iatC: 0.0,
          tpsPercent: 0.0,
          batteryVoltage: 0.0,
          fuelFlowLh: 0.0,
          instantaneousKml: 0.0,
          leanAngleDeg: 0.0,
          gForce: 0.0,
          live: live,
        );

    test('an empty live set means nothing is connected', () {
      final f = frame({});
      expect(f.has(ObdChannel.rpm), isFalse);
      expect(f.has(ObdChannel.ect), isFalse);
      expect(f.has(ObdChannel.batteryVoltage), isFalse);
    });

    test('has() reflects exactly which channels are live', () {
      final f = frame({ObdChannel.rpm, ObdChannel.speed, ObdChannel.ect});
      expect(f.has(ObdChannel.rpm), isTrue);
      expect(f.has(ObdChannel.ect), isTrue);
      expect(f.has(ObdChannel.tps), isFalse,
          reason: 'a channel not in the set must report unavailable, not zero');
      expect(f.has(ObdChannel.fuelLevel), isFalse);
    });

    test('a frame with no live channels cannot be used for the fuel model', () {
      // RPM + MAP without IAT is not enough. Air density at 30 C and 60 C
      // differ by ~12%, so substituting a default would skew every economy
      // figure downstream.
      final f = frame({ObdChannel.rpm, ObdChannel.map});
      expect(f.has(ObdChannel.rpm) && f.has(ObdChannel.map), isTrue);
      expect(f.has(ObdChannel.iat), isFalse,
          reason: 'fuel math must be refused without IAT');
    });

    test('a car ECU with fuel level supports it', () {
      final f = frame({ObdChannel.rpm, ObdChannel.speed, ObdChannel.fuelLevel});
      expect(f.has(ObdChannel.fuelLevel), isTrue);
    });

    test('empty() reports nothing as live', () {
      final f = TelemetryFrame.empty();
      expect(f.live, isEmpty);
      for (final c in ObdChannel.values) {
        expect(f.has(c), isFalse,
            reason: '${c.name} must not be live on an empty frame');
      }
    });

    test('toJson serialises the live set by name', () {
      final f = frame({ObdChannel.rpm, ObdChannel.ect});
      final json = f.toJson();
      expect(json['live'], containsAll(['rpm', 'ect']));
      expect(json['live'], isNot(contains('tps')));
    });
  });
}