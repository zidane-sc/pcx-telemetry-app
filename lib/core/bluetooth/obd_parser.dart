import 'dart:convert';

import '../models/telemetry_data.dart';

/// Why an ELM327 response cannot be decoded.
enum ObdReply {
  /// The ECU answered with a valid multi-byte response.
  ok,

  /// `NO DATA` — the ECU does not implement this PID. Normal on a motorcycle,
  /// not a fault.
  noData,

  /// `?` or an unrecognised token. Usually a baud-rate or protocol mismatch,
  /// which is what a K-Line bike looks like when the dongle is still on the
  /// default 38400.
  malformed,

  /// Empty or only prompt noise.
  empty,

  /// A recognised header with too few bytes to be the response.
  truncated,
}

class ObdParseResult {
  final ObdReply status;
  final double? value;

  const ObdParseResult(this.status, this.value);

  bool get isOk => status == ObdReply.ok && value != null;

  const ObdParseResult.ok(double v) : this(ObdReply.ok, v);
  const ObdParseResult.fail(ObdReply s) : this(s, null);
}

/// Decodes ELM327 PID responses into physical units.
///
/// Pure functions over strings, with no Bluetooth or timing involved, so every
/// case — including the failure modes that only appear on real hardware — is
/// unit-testable on the build server.
///
/// The design rule here is that a decode either produces a value the ECU
/// actually sent, or produces nothing. An earlier version kept a plausible
/// default on failure, which meant an unsupported PID looked identical to a
/// sensor reading 30 °C forever.
class ObdParser {
  /// Canonical tokens, uppercase, whitespace stripped.
  static String _clean(String raw) =>
      raw.replaceAll(RegExp(r'\s'), '').toUpperCase();

  /// Classifies a response before attempting a decode.
///
/// Order matters. `SEARCHING...` and `BUS INIT` contain no PID header but do
  /// indicate the dongle is alive and hunting for a protocol, which is very
  /// different from `NO DATA` (ECU found, PID absent).
  static ObdReply classify(String raw) {
    final c = _clean(raw);
    if (c.isEmpty) return ObdReply.empty;
    if (c.contains('NODATA') || c.contains('STOPPED')) return ObdReply.noData;
    if (c == '?' || c.contains('UNABLETOCONNECT')) return ObdReply.malformed;

    final body = c.replaceAll('>', '');

    // A response the ECU found but where every payload byte is zero means the
    // PID is not implemented. ELM327 reports this as `41 01 00 00 00 00 00 00`
    // rather than `NO DATA` on some adapters.
    if (_isAllZeroPayload(body)) return ObdReply.noData;

    // Any non-hex byte means the line framing or baud rate is wrong -- the
    // signature of a K-Line bike talking to a dongle still on the default
    // 38400, and of a line where two responses merged into one.
    if (!RegExp(r'^[0-9A-F?]+$').hasMatch(body)) return ObdReply.malformed;

    // Two `41` headers in one response is a framing error, never valid data.
    // A legitimate multi-frame PID repeat (mode 06/07 service modes) is
    // separated by the prompt, so it arrives as separate lines, not one body.
    final headerCount = RegExp(r'41[0-9A-F]{2}').allMatches(body).length;
    if (headerCount > 1) return ObdReply.malformed;

    return ObdReply.ok;
  }

  /// True when the response looks like `4X <mode> 00 00 00 ...` with every data
  /// byte zero.
  static bool _isAllZeroPayload(String body) {
    final m = RegExp(r'^4[0-9A-F][0-9A-F]{2}((?:[0-9A-F]{2})+)$').firstMatch(body);
    if (m == null) return false;
    final payload = m.group(1)!;
    if (payload.length < 4) return false;
    return RegExp(r'^(00)+$').hasMatch(payload);
  }

  /// Extracts the PID body from [raw], tolerating a leading banner.
  ///
  /// Some ELM327 clones prefix the first response after reset with a firmware
  /// banner (`ELM327 v1.5`) on the same line. Strict hex validation over the
  /// whole line would reject a perfectly good PID response because of it, so
  /// validation runs on the body from the header onwards instead.
  static String _bodyFrom(String raw, String header) {
    final c = _clean(raw).replaceAll('>', '');
    final idx = c.indexOf(header);
    if (idx < 0) return '';
    return c.substring(idx);
  }

  /// Extracts the value bytes following [header] in [raw].
  static ObdParseResult _multiByte(
    String raw,
    String header, {
    required double transform(int a, int b),
  }) {
    final c = _clean(raw);
    final headerLevel = classify(raw);
    // A banner in front of a valid header is fine; only classify strictly when
    // there is no header to fall back on.
    if (headerLevel == ObdReply.noData) {
      return ObdParseResult.fail(headerLevel);
    }

    final c2 = _bodyFrom(raw, header);
    if (c2.isEmpty) {
      return ObdParseResult.fail(
          headerLevel == ObdReply.empty ? ObdReply.empty : ObdReply.malformed);
    }

    final idx = 0;
    final hex = c2.substring(header.length);
    if (hex.length < 4) return const ObdParseResult.fail(ObdReply.truncated);

    final a = int.tryParse(hex.substring(0, 2), radix: 16);
    final b = int.tryParse(hex.substring(2, 4), radix: 16);
    if (a == null || b == null) return const ObdParseResult.fail(ObdReply.malformed);

    return ObdParseResult.ok(transform(a, b));
  }

  /// Extracts a single value byte following [header].
  static ObdParseResult _singleByte(
    String raw,
    String header, {
    required double transform(int a),
  }) {
    final status = classify(raw);
    if (status == ObdReply.noData) {
      return ObdParseResult.fail(status);
    }

    final body = _bodyFrom(raw, header);
    if (body.isEmpty) {
      return ObdParseResult.fail(
          status == ObdReply.empty ? ObdReply.empty : ObdReply.malformed);
    }

    final hex = body.substring(header.length);
    if (hex.length < 2) return const ObdParseResult.fail(ObdReply.truncated);

    final a = int.tryParse(hex.substring(0, 2), radix: 16);
    if (a == null) return const ObdParseResult.fail(ObdReply.malformed);

    return ObdParseResult.ok(transform(a));
  }

  /// Engine speed, PID 010C. `(A*256 + B) / 4` rpm.
  static ObdParseResult rpm(String raw) => _multiByte(raw, '410C',
      transform: (a, b) => ((a * 256.0) + b) / 4.0);

  /// Road speed, PID 010D, km/h.
  static ObdParseResult speed(String raw) =>
      _singleByte(raw, '410D', transform: (a) => a.toDouble());

  /// Manifold absolute pressure, PID 010B, kPa.
  static ObdParseResult map(String raw) =>
      _singleByte(raw, '410B', transform: (a) => a.toDouble());

  /// Throttle position, PID 0111. `A / 255 * 100` percent.
  static ObdParseResult tps(String raw) =>
      _singleByte(raw, '4111', transform: (a) => (a * 100.0) / 255.0);

  /// Calculated engine load, PID 0104. `A / 255 * 100` percent.
  static ObdParseResult engineLoad(String raw) =>
      _singleByte(raw, '4104', transform: (a) => (a * 100.0) / 255.0);

  /// Timing advance, PID 010E. `(A - 128) / 2` degrees.
  static ObdParseResult timingAdvance(String raw) =>
      _singleByte(raw, '410E', transform: (a) => (a - 128) / 2.0);

  /// Engine coolant temperature, PID 0105. `A - 40` °C.
  static ObdParseResult ect(String raw) =>
      _singleByte(raw, '4105', transform: (a) => (a - 40).toDouble());

  /// Intake air temperature, PID 010F. `A - 40` °C.
  static ObdParseResult iat(String raw) =>
      _singleByte(raw, '410F', transform: (a) => (a - 40).toDouble());

  /// Fuel tank level, PID 012F. `A / 255 * 100` percent.
  ///
  /// Absent on most commuter motorcycles — the float feeds the dash cluster
  /// directly instead of the ECU.
  static ObdParseResult fuelLevel(String raw) =>
      _singleByte(raw, '412F', transform: (a) => (a * 100.0) / 255.0);

  /// Battery voltage. `ATRV` answers in ASCII volts, not hex.
  static ObdParseResult batteryVoltage(String raw) {
    final c = _clean(raw);
    if (c.isEmpty) return const ObdParseResult.fail(ObdReply.empty);

    // ATRV can answer `12.6V`, or `NO DATA`, or the prompt echo.
    final m = RegExp(r'^(\d{1,2}(?:\.\d)?)V?$').firstMatch(c);
    if (m == null) {
      return ObdParseResult.fail(
          c.contains('NODATA') ? ObdReply.noData : ObdReply.malformed);
    }
    final v = double.tryParse(m.group(1)!);
    // Outside 5–20 V the reading is noise, not a measurement.
    if (v == null || v < 5.0 || v > 20.0) {
      return const ObdParseResult.fail(ObdReply.malformed);
    }
    return ObdParseResult.ok(v);
  }

  /// ECU odometer, PID 01A6, four bytes, `value / 10` km.
  ///
  /// Rarely implemented outside of mode 09 service tools; a PCX will not have
  /// it. Kept because some ECUs do, and because the Garage base-odometer sync
  /// needs a source of truth when one exists.
  static ObdParseResult ecuOdometer(String raw) {
    final c = _clean(raw);
    final status = classify(raw);
    if (status != ObdReply.ok) return ObdParseResult.fail(status);

    final idx = c.indexOf('41A6');
    if (idx < 0) return const ObdParseResult.fail(ObdReply.malformed);

    final hex = c.substring(idx + 4);
    if (hex.length < 8) return const ObdParseResult.fail(ObdReply.truncated);

    final val = int.tryParse(hex.substring(0, 8), radix: 16);
    if (val == null) return const ObdParseResult.fail(ObdReply.malformed);
    return ObdParseResult.ok(val / 10.0);
  }

  /// Decodes a stored DTC read, for the pre-ride scan.
  static ObdParseResult storedDtc(String raw) {
    final c = _clean(raw);
    if (c.contains('NODATA')) {
      return const ObdParseResult.fail(ObdReply.noData);
    }
    if (c.isEmpty) return const ObdParseResult.fail(ObdReply.empty);
    return ObdParseResult.ok(double.tryParse(c) ?? 0.0);
  }

  /// Decodes the ELM327 `0100` compatibility bitmap.
  ///
  /// Returns true only when the mask is present AND has at least one bit set.
  /// An all-zero mask is the ECU reporting "I speak this protocol but I
  /// implement no mode-01 PIDs" -- a real answer, but not a usable link, and
  /// treating it as success is what let a silent ECU look connected.
  static bool hasSupportedPids(String raw) {
    final c = _clean(raw).replaceAll('>', '');
    if (c.isEmpty || c.contains('NODATA')) return false;
    final idx = c.indexOf('4100');
    if (idx < 0) return false;
    final mask = c.substring(idx + 4);
    if (mask.length < 4) return false;
    return RegExp(r'[1-9A-F]').hasMatch(mask);
  }
}

/// Parses an ASCII serial chunk into lines.
///
/// Exposed because the "one `>` prompt per response" assumption is the single
/// most fragile part of the transport layer, and it needs to be testable
/// without a Bluetooth socket.
class ObdLineParser {
  /// A plain String, not a StringBuffer: draining completed lines from the
  /// middle needs `removeRange`, which StringBuffer does not have, and the
  /// buffer never exceeds one ELM327 response in practice.
  String _buffer = '';

  /// Feeds a raw chunk and returns whatever complete lines it completed.
  List<String> feed(String chunk) {
    _buffer += chunk;
    final lines = <String>[];
    while (true) {
      final i = _buffer.indexOf('\r');
      if (i < 0) break;
      final line = _buffer.substring(0, i);
      _buffer = _buffer.substring(i + 1);
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) lines.add(trimmed);
    }
    return lines;
  }

  /// The prompt character, delivered out of band because it terminates the
  /// current response rather than ending a line.
  static const String prompt = '>';

  void clear() => _buffer = '';
}

/// Decodes a byte payload the way the Bluetooth stream delivers it.
///
/// Kept separate so the ASCII behaviour can be tested: `ascii.decode` with
/// `allowInvalid: true` silently drops high bytes, which is correct for ELM327
/// output and would be data loss for a binary protocol.
String decodeSerialChunk(List<int> data) =>
    ascii.decode(data, allowInvalid: true);