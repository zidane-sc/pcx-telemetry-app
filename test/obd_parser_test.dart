import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/bluetooth/obd_parser.dart';

void main() {
  group('classify', () {
    test('an empty response is empty', () {
      expect(ObdParser.classify(''), ObdReply.empty);
      expect(ObdParser.classify('   '), ObdReply.empty);
      expect(ObdParser.classify('\r\n'), ObdReply.empty);
    });

    test('NO DATA is recognised, on every spelling ELM327 emits', () {
      expect(ObdParser.classify('NO DATA'), ObdReply.noData);
      expect(ObdParser.classify('NODATA'), ObdReply.noData);
      expect(ObdParser.classify('41 01 00 00 00 00 00 00\r>'), ObdReply.noData);
      expect(ObdParser.classify('STOPPED'), ObdReply.noData);
    });

    test('a bare question mark is malformed, not empty', () {
      // `?` is the ELM327's "I have no idea what this command means", which on
      // a K-Line bike is the signature of a baud-rate mismatch. Treating it as
      // empty hides the single most useful diagnostic.
      expect(ObdParser.classify('?'), ObdReply.malformed);
    });

    test('junk from a baud mismatch is malformed', () {
      // What a 10400-baud K-Line stream actually looks like through a dongle
      // left on 38400: printable noise, not the non-ASCII bytes a naive test
      // would reach for (ascii.decode drops high bytes before we ever see them).
      expect(ObdParser.classify('~~z~#k'), ObdReply.malformed);
      expect(ObdParser.classify('4105FF4105FF'), ObdReply.malformed,
          reason: 'two headers in one body means the framing is wrong');
    });

    test('a normal response classifies as ok', () {
      expect(ObdParser.classify('41 0C 1A F8'), ObdReply.ok);
      expect(ObdParser.classify('410C1AF8'), ObdReply.ok);
    });
  });

  group('rpm (010C)', () {
    test('decodes the documented formula', () {
      // (0x1A * 256 + 0xF8) / 4 = (6656 + 248)/4 = 1726 rpm
      final r = ObdParser.rpm('41 0C 1A F8');
      expect(r.isOk, isTrue);
      expect(r.value, closeTo(1726.0, 0.01));
    });

    test('idle is around 1500', () {
      // (0x17 * 256 + 0x70) / 4 = (5888 + 112) / 4 = 1500
      expect(ObdParser.rpm('410C1770')!.value, closeTo(1500.0, 0.01));
    });

    test('NO DATA yields no value rather than a zero', () {
      final r = ObdParser.rpm('NO DATA');
      expect(r.status, ObdReply.noData);
      expect(r.value, isNull);
    });

    test('a truncated response is rejected', () {
      expect(ObdParser.rpm('41 0C 1A').status, ObdReply.truncated);
    });
  });

  group('speed (010D)', () {
    test('decodes km/h directly', () {
      expect(ObdParser.speed('41 0D 32')!.value, 50.0);
    });

    test('zero is a real reading, not a failure', () {
      final r = ObdParser.speed('41 0D 00');
      expect(r.isOk, isTrue);
      expect(r.value, 0.0);
    });
  });

  group('map (010B)', () {
    test('decodes kPa directly', () {
      expect(ObdParser.map('41 0B 26')!.value, 38.0);
      expect(ObdParser.map('410B65')!.value, 101.0);
    });
  });

  group('tps (0111)', () {
    test('scales to percent', () {
      expect(ObdParser.tps('41 11 00')!.value, 0.0);
      expect(ObdParser.tps('41 11 80')!.value, closeTo(50.2, 0.1));
      expect(ObdParser.tps('41 11 FF')!.value, closeTo(100.0, 0.1));
    });
  });

  group('engine load (0104)', () {
    test('scales to percent', () {
      expect(ObdParser.engineLoad('41 04 64')!.value, closeTo(39.2, 0.1));
    });
  });

  group('timing advance (010E)', () {
    test('centres on zero at 0x80', () {
      // (A - 128) / 2, so each byte step is half a degree.
      expect(ObdParser.timingAdvance('41 0E 80')!.value, 0.0);
      expect(ObdParser.timingAdvance('41 0E 90')!.value, 8.0); // +16/2
      expect(ObdParser.timingAdvance('41 0E 70')!.value, -8.0);
      expect(ObdParser.timingAdvance('41 0E A0')!.value, 16.0); // +32/2
    });
  });

  group('coolant temperature (0105)', () {
    test('offsets by 40', () {
      expect(ObdParser.ect('41 05 5A')!.value, 50.0);
      expect(ObdParser.ect('41 05 7B')!.value, 83.0);
    });

    test('NO DATA does not become a plausible-looking 30 degrees', () {
      // This is the bug the whole module exists to prevent: an unsupported
      // coolant sensor reporting a comfortable room temperature forever.
      final r = ObdParser.ect('NO DATA');
      expect(r.value, isNull);
    });
  });

  group('intake air temperature (010F)', () {
    test('offsets by 40', () {
      expect(ObdParser.iat('41 0F 5E')!.value, 54.0);
    });
  });

  group('fuel level (012F)', () {
    test('scales to percent', () {
      expect(ObdParser.fuelLevel('41 2F FF')!.value, closeTo(100.0, 0.1));
      expect(ObdParser.fuelLevel('41 2F 80')!.value, closeTo(50.2, 0.1));
    });

    test('absent on a typical commuter motorcycle', () {
      expect(ObdParser.fuelLevel('NO DATA').status, ObdReply.noData);
    });
  });

  group('battery voltage (ATRV)', () {
    test('reads ASCII volts', () {
      expect(ObdParser.batteryVoltage('12.6V')!.value, 12.6);
      expect(ObdParser.batteryVoltage('14.2')!.value, 14.2);
      expect(ObdParser.batteryVoltage('13.8 V')!.value, 13.8);
    });

    test('rejects readings outside the plausible 5-20 V range', () {
      // A dropped byte turns "14.2" into "1.2" or "142"; neither is a battery.
      expect(ObdParser.batteryVoltage('0.0V').status, ObdReply.malformed);
      expect(ObdParser.batteryVoltage('44.2V').status, ObdReply.malformed);
      expect(ObdParser.batteryVoltage('??').status, ObdReply.malformed);
    });

    test('distinguishes NO DATA from a bad reading', () {
      expect(ObdParser.batteryVoltage('NO DATA').status, ObdReply.noData);
    });
  });

  group('ECU odometer (01A6)', () {
    test('decodes four bytes and scales to km', () {
      // 0x000186A0 = 100000 -> 10000.0 km
      final r = ObdParser.ecuOdometer('41 A6 00 01 86 A0');
      expect(r.isOk, isTrue);
      expect(r.value, closeTo(10000.0, 0.01));
    });

    test('rejects a short response', () {
      expect(ObdParser.ecuOdometer('41 A6 00').status, ObdReply.truncated);
    });

    test('a PCX does not have this PID', () {
      expect(ObdParser.ecuOdometer('NO DATA').status, ObdReply.noData);
    });
  });

  group('whitespace and framing tolerance', () {
    test('spaces between bytes do not matter', () {
      final spaced = ObdParser.ect('  41 05 7B\r\n');
      final tight = ObdParser.ect('41057B');
      expect(spaced.value, tight.value);
      expect(spaced.value, 83.0);
    });

    test('a trailing prompt does not break the decode', () {
      expect(ObdParser.rpm('41 0C 1A F8\r>')!.value, closeTo(1726.0, 0.01));
    });

    test('a leading protocol banner is skipped', () {
      // ATZ/ATSP responses can prepend a banner on some ELM327 clones.
      expect(ObdParser.ect('ELM327 v1.5\r41 05 7B')!.value, 83.0);
    });
  });

  group('ObdLineParser', () {
    test('splits on carriage returns', () {
      final p = ObdLineParser();
      expect(p.feed('41 0C 1A F8\r'), ['41 0C 1A F8']);
    });

    test('buffers a partial line until it completes', () {
      final p = ObdLineParser();
      expect(p.feed('41 0C'), isEmpty);
      expect(p.feed(' 1A F8\r'), ['41 0C 1A F8']);
    });

    test('emits several lines from one chunk', () {
      final p = ObdLineParser();
      expect(p.feed('BUS INIT\rOK\r'), ['BUS INIT', 'OK']);
    });

    test('skips blank lines', () {
      final p = ObdLineParser();
      expect(p.feed('\r\r41 05 7B\r\r'), ['41 05 7B']);
    });

    test('clear discards the partial buffer', () {
      final p = ObdLineParser();
      p.feed('41 0C 1A');
      p.clear();
      expect(p.feed('F8\r'), ['F8'],
          reason: 'the discarded prefix must not resurface');
    });
  });

  group('hasSupportedPids', () {
    test('true when the dongle reports a compatibility mask', () {
      expect(ObdParser.hasSupportedPids('41 00 BE 3F B8 11 92'), isTrue);
    });

    test('false when nothing was found', () {
      expect(ObdParser.hasSupportedPids('NO DATA'), isFalse);
      expect(ObdParser.hasSupportedPids(''), isFalse);
      expect(ObdParser.hasSupportedPids('?'), isFalse);
    });
  });
}