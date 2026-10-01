import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import '../models/telemetry_data.dart';
import '../models/vehicle_profile.dart';
import '../telemetry/speed_density_calculator.dart';
import 'obd_parser.dart';

enum ObdConnectionState {
  disconnected,
  connecting,
  handshaking,
  connected,

  /// The dongle answered AT commands but no PID comes back. Usually a baud or
  /// protocol mismatch on a K-Line bike, and a completely different problem
  /// from `disconnected`.
  ecuSilent,

  error,
}

/// Why the ECU is not answering, when it is not.
enum ObdFault {
  none,

  /// The dongle itself never identified. Wrong MAC, PIN, or not powered.
  dongleMissing,

  /// The dongle is fine but every PID returns NO DATA / garbage. On a
  /// motorcycle this is nearly always a protocol or baud mismatch.
  protocolMismatch,

  /// The dongle answered but the ECU never responded at all.
  noEcuResponse,
}

/// One decoded PID sample.
class ObdReading {
  final ObdChannel channel;
  final double value;
  final ObdReply status;
  const ObdReading(this.channel, this.value, this.status);

  bool get ok => status == ObdReply.ok;
}

/// The result of a handshake, kept for the Garage diagnostics screen.
class ObdHandshakeReport {
  final bool dongleIdentified;
  final String? dongleId;
  final ObdFault fault;
  final ObdReply lastReply;
  final Set<ObdChannel> supportedPids;
  final List<String> transcript;

  const ObdHandshakeReport({
    required this.dongleIdentified,
    required this.dongleId,
    required this.fault,
    required this.lastReply,
    required this.supportedPids,
    required this.transcript,
  });
}

class ObdService {
  final StreamController<TelemetryFrame> _telemetryController =
      StreamController<TelemetryFrame>.broadcast();
  Stream<TelemetryFrame> get telemetryStream => _telemetryController.stream;

  final StreamController<ObdConnectionState> _stateController =
      StreamController<ObdConnectionState>.broadcast();
  Stream<ObdConnectionState> get stateStream => _stateController.stream;

  ObdConnectionState _state = ObdConnectionState.disconnected;
  ObdConnectionState get state => _state;

  /// Set while the ECU is silent, so the UI can say why instead of just
  /// showing dashes.
  ObdFault _fault = ObdFault.none;
  ObdFault get fault => _fault;

  ObdHandshakeReport? _lastHandshake;
  ObdHandshakeReport? get lastHandshake => _lastHandshake;

  BluetoothConnection? _connection;
  final SpeedDensityCalculator _calculator = const SpeedDensityCalculator();
  final ObdLineParser _lineParser = ObdLineParser();

  bool _isMockMode = false;
  bool get isMockMode => _isMockMode;
  Timer? _mockTimer;
  Timer? _pollingTimer;
  bool _polling = false;

  final List<String> _transcript = [];

  /// Value cache. Each entry is null until the ECU has answered that PID at
  /// least once, and stays null if the ECU does not implement it.
  final Map<ObdChannel, double?> _values = {};
  final Set<ObdChannel> _live = {};

  double _rpm = 0.0, _speed = 0.0, _map = 101.3, _tps = 0.0;
  double _ect = 0.0, _iat = 0.0, _volt = 0.0, _load = 0.0;
  double _timing = 0.0, _fuelLevel = 0.0, _ecuOdo = 0.0;

  ObdService() {
    // Every channel starts unknown, not zero. A gauge that shows 0 °C before
    // the ECU has ever answered is making a claim it cannot support.
    for (final c in ObdChannel.values) {
      _values[c] = null;
    }
  }

  void enableMockMode(bool enable) {
    _isMockMode = enable;
    if (_isMockMode) {
      _startMockSimulation();
      _setState(ObdConnectionState.connected);
    } else {
      _mockTimer?.cancel();
      _setState(ObdConnectionState.disconnected);
    }
  }

  void _setState(ObdConnectionState s) {
    _state = s;
    _stateController.add(s);
  }

  void _startMockSimulation() {
    _mockTimer?.cancel();
    double mockTps = 0.0;
    bool opening = true;

    _mockTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!_isMockMode) return;
      if (opening) {
        mockTps += 2.5;
        if (mockTps >= 65.0) opening = false;
      } else {
        mockTps -= 1.8;
        if (mockTps <= 0.0) {
          mockTps = 0.0;
          opening = true;
        }
      }
      _rpm = 1500.0 + (mockTps * 95.0);
      _speed = _rpm > 2200.0 ? (_rpm - 2200.0) / 75.0 : 0.0;
      _map = 38.0 + (mockTps * 0.7);
      _ect = 88.0 + (mockTps * 0.05);
      _iat = 34.0;
      _volt = 14.2;
      _load = (mockTps * 1.2).clamp(12.0, 95.0);
      _timing = 12.0 + (_rpm / 400.0);
      _fuelLevel = 75.0;
      _live.addAll(const [
        ObdChannel.rpm, ObdChannel.speed, ObdChannel.map, ObdChannel.tps,
        ObdChannel.engineLoad, ObdChannel.timingAdvance, ObdChannel.ect,
        ObdChannel.iat, ObdChannel.batteryVoltage, ObdChannel.fuelLevel,
      ]);
      _emitTelemetryFrame();
    });
  }

  /// Connects and verifies the ECU actually answers.
  ///
  /// The previous version set `connected` immediately after sending ATSP,
  /// without checking any response. That is the same shape of bug as the dead
  /// `isObdConnected` alert path in Sprint 1: the UI claimed a working link
  /// that did not exist, and every downstream consumer trusted it.
  Future<bool> connect(
    String macAddress, {
    ObdProtocolType protocol = ObdProtocolType.kwp2000Fast,
  }) async {
    if (_isMockMode) return true;

    _transcript.clear();
    _fault = ObdFault.none;

    try {
      _setState(ObdConnectionState.connecting);
      _connection = await BluetoothConnection.toAddress(macAddress);

      _lineParser.clear();
      _connection!.input?.listen(_onDataReceived,
          onDone: disconnect,
          onError: (e) {
            debugPrint('[ObdService] serial error: $e');
            disconnect();
          });

      _setState(ObdConnectionState.handshaking);

      // Identify the dongle. Without this response there is no adapter at all.
      final id = await _sendCommand('ATZ', timeout: const Duration(seconds: 3));
      if (!id.contains('ELM')) {
        _fault = ObdFault.dongleMissing;
        _recordHandshake(false, id, ObdReply.empty);
        debugPrint('[ObdService] No ELM327 identifier. Got: "$id"');
        disconnect();
        return false;
      }

      await _sendCommand('ATE0');
      await _sendCommand('ATL0');
      await _sendCommand('ATS0');
      // ATSP picks the protocol; ATS0/ATSP do not change the ELM327's own
      // serial baud, which is a separate setting the dongle negotiates itself
      // during the five-baud init. Do not force it here -- overwriting it is
      // what breaks K-Line bikes on clones that do not support the command.
      await _sendCommand('ATSP${protocol.atspValue}');

      // Probe: read the supported-PID bitmap. This is the one request that
      // distinguishes "dongle alive, ECU found, no PIDs" from "nothing here".
      final probe = await _sendCommand('0100', timeout: const Duration(seconds: 3));
      final probeStatus = ObdParser.classify(probe);
      final hasPids = ObdParser.hasSupportedPids(probe);

      if (!hasPids) {
        _fault = probeStatus == ObdReply.malformed
            ? ObdFault.protocolMismatch
            : ObdFault.noEcuResponse;
        _recordHandshake(true, id, probeStatus);
        debugPrint(
            '[ObdService] No PID bitmap. status=$probeStatus raw="$probe"');
        _setState(ObdConnectionState.ecuSilent);
        _emitTelemetryFrame();
        return false;
      }

      // Populate the supported set from the bitmap so the UI can grey out PIDs
      // this ECU will never provide instead of waiting for a NO DATA first.
      _parseSupportedPids(probe);

      _recordHandshake(true, id, probeStatus);
      _setState(ObdConnectionState.connected);
      _startRealPollingLoop();
      return true;
    } catch (e) {
      debugPrint('[ObdService] connect error: $e');
      _fault = ObdFault.dongleMissing;
      _setState(ObdConnectionState.error);
      disconnect();
      return false;
    }
  }

  void _recordHandshake(
      bool identified, String? id, ObdReply last) {
    _lastHandshake = ObdHandshakeReport(
      dongleIdentified: identified,
      dongleId: id,
      fault: _fault,
      lastReply: last,
      supportedPids: Set.of(_live),
      transcript: List.of(_transcript),
    );
  }

  /// Reads the PID support bitmap (`41 00 <4 mask bytes>`).
  ///
  /// Bit n of byte n/8, MSB first, means mode 01 PID (n+1) is supported.
  void _parseSupportedPids(String raw) {
    final c = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
    final idx = c.indexOf('4100');
    if (idx < 0) return;
    final hex = c.substring(idx + 4);
    if (hex.length < 8) return;

    const pidToChannel = {
      4: ObdChannel.engineLoad, // 0104
      5: ObdChannel.ect, // 0105
      11: ObdChannel.map, // 010B
      12: ObdChannel.rpm, // 010C
      13: ObdChannel.speed, // 010D
      15: ObdChannel.iat, // 010F
      31: ObdChannel.tps, // 0111
      47: ObdChannel.fuelLevel, // 012F
    };

    for (var pid = 1; pid <= 32; pid++) {
      final byteIdx = (pid - 1) ~/ 8;
      final bitIdx = 7 - ((pid - 1) % 8);
      if (byteIdx * 2 + 2 > hex.length) break;
      final byte = int.tryParse(hex.substring(byteIdx * 2, byteIdx * 2 + 2),
          radix: 16);
      if (byte == null) continue;
      if ((byte >> bitIdx) & 1 != 1) continue;
      final ch = pidToChannel[pid];
      if (ch != null) _live.add(ch);
    }
  }

  void _onDataReceived(Uint8List data) {
    final chunk = decodeSerialChunk(data);
    for (final line in _lineParser.feed(chunk)) {
      if (line.length > 200) continue; // banner noise
      _transcript.add(line);
      if (_transcript.length > 60) _transcript.removeAt(0);
    }

    // The prompt terminates the current response.
    if (chunk.contains(ObdLineParser.prompt)) {
      final response = _transcript.isEmpty ? '' : _transcript.join(' ');
      _transcript.clear();
      final completer = _pendingCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(response);
        _pendingCompleter = null;
      }
    }
  }

  Completer<String>? _pendingCompleter;

  Future<String> _sendCommand(String cmd,
      {Duration timeout = const Duration(milliseconds: 1500)}) async {
    if (_connection == null || !_connection!.isConnected) return '';
    _transcript.clear();
    _pendingCompleter = Completer<String>();
    try {
      _connection!.output.add(Uint8List.fromList(ascii.encode('$cmd\r')));
      await _connection!.output.allSent;
      return await _pendingCompleter!.future.timeout(timeout, onTimeout: () {
        debugPrint('[ObdService] "$cmd" timed out');
        return '';
      });
    } catch (e) {
      debugPrint('[ObdService] "$cmd" error: $e');
      return '';
    }
  }

  /// The PIDs worth polling, in priority order.
  ///
  /// Ordered by how much the app actually uses them: RPM and TPS drive the
  /// rule engine and engine-brake detection, then the fuel math inputs, then
  /// the display-only channels. Anything the support bitmap said the ECU lacks
  /// is skipped entirely rather than sending a command that will answer NO
  /// DATA forever.
  static const List<(String, ObdChannel, ObdParseResult Function(String))>
      _pollPlan = [
    ('010C', ObdChannel.rpm, ObdParser.rpm),
    ('0111', ObdChannel.tps, ObdParser.tps),
    ('010B', ObdChannel.map, ObdParser.map),
    ('0105', ObdChannel.ect, ObdParser.ect),
    ('ATRV', ObdChannel.batteryVoltage, ObdParser.batteryVoltage),
    ('010D', ObdChannel.speed, ObdParser.speed),
    ('010F', ObdChannel.iat, ObdParser.iat),
    ('0104', ObdChannel.engineLoad, ObdParser.engineLoad),
    ('012F', ObdChannel.fuelLevel, ObdParser.fuelLevel),
  ];

  void _startRealPollingLoop() {
    _pollingTimer?.cancel();
    var cursor = 0;
    var idleRounds = 0;

    _pollingTimer =
        Timer.periodic(const Duration(milliseconds: 80), (timer) async {
      if (_state != ObdConnectionState.connected) return;
      // One request in flight at a time. Overlapping commands on a Bluetooth
      // serial link interleave responses and corrupt every parse.
      if (_polling) return;
      _polling = true;

      try {
        var sent = false;
        for (var i = 0; i < _pollPlan.length; i++) {
          final idx = (cursor + i) % _pollPlan.length;
          final (cmd, channel, decode) = _pollPlan[idx];
          // Skip a PID the support bitmap already ruled out. Keep polling it
          // anyway if we have never seen a bitmap, since some ECUs answer a PID
          // while reporting the bit as clear.
          if (_live.isNotEmpty && !_live.contains(channel)) continue;
          if (!channelIsPollable(channel)) continue;

          cursor = (idx + 1) % _pollPlan.length;
          sent = true;

          final raw = await _sendCommand(cmd);
          final res = decode(raw);
          if (res.isOk) {
            _values[channel] = res.value!;
            _live.add(channel);
            idleRounds = 0;
          } else if (res.status == ObdReply.noData) {
            // The ECU does not implement this PID. That is normal on a
            // motorcycle, and it must remove the channel from `live` rather
            // than leave a stale value on screen.
            _live.remove(channel);
            _values[channel] = null;
          } else {
            idleRounds++;
          }
          break;
        }

        if (!sent) {
          // Nothing pollable: the ECU reports no PIDs we use.
          _fault = ObdFault.protocolMismatch;
          _setState(ObdConnectionState.ecuSilent);
          return;
        }

        // Three consecutive unexplained replies means the link is not really
        // working, however connected we believe we are.
        if (idleRounds >= 3) {
          _fault = ObdFault.protocolMismatch;
          _setState(ObdConnectionState.ecuSilent);
          debugPrint('[ObdService] 3 consecutive undecodable replies');
          return;
        }

        _emitTelemetryFrame();
      } catch (e) {
        debugPrint('[ObdService] poll error: $e');
      } finally {
        _polling = false;
      }
    });
  }

  /// Timing advance and odometer are read on demand, not polled: neither
  /// drives anything in the cockpit, and 01A6 costs a full second to answer NO
  /// DATA on every motorcycle.
  static bool channelIsPollable(ObdChannel c) =>
      c != ObdChannel.timingAdvance && c != ObdChannel.ecuOdometer;

  Future<ObdReading> readOnDemand(ObdChannel channel) async {
    switch (channel) {
      case ObdChannel.timingAdvance:
        return _read('010E', channel, ObdParser.timingAdvance);
      case ObdChannel.ecuOdometer:
        return _read('01A6', channel, ObdParser.ecuOdometer);
      default:
        return ObdReading(channel, 0.0, ObdReply.empty);
    }
  }

  Future<ObdReading> _read(
    String cmd,
    ObdChannel channel,
    ObdParseResult Function(String) decode,
  ) async {
    if (_state != ObdConnectionState.connected) {
      return ObdReading(channel, 0.0, ObdReply.empty);
    }
    final raw = await _sendCommand(cmd, timeout: const Duration(seconds: 2));
    final res = decode(raw);
    if (res.isOk) {
      _values[channel] = res.value!;
      _live.add(channel);
      _applyValue(channel, res.value!);
    } else if (res.status == ObdReply.noData) {
      _live.remove(channel);
      _values[channel] = null;
    }
    _emitTelemetryFrame();
    return ObdReading(channel, res.value ?? 0.0, res.status);
  }

  /// Applies a decoded value to the flat fields used by the fuel model.
  void _applyValue(ObdChannel channel, double v) {
    switch (channel) {
      case ObdChannel.rpm:
        _rpm = v;
      case ObdChannel.speed:
        _speed = v;
      case ObdChannel.map:
        _map = v;
      case ObdChannel.tps:
        _tps = v;
      case ObdChannel.ect:
        _ect = v;
      case ObdChannel.iat:
        _iat = v;
      case ObdChannel.batteryVoltage:
        _volt = v;
      case ObdChannel.engineLoad:
        _load = v;
      case ObdChannel.timingAdvance:
        _timing = v;
      case ObdChannel.fuelLevel:
        _fuelLevel = v;
      case ObdChannel.ecuOdometer:
        _ecuOdo = v;
    }
  }

  void _emitTelemetryFrame() {
    // Every poll cycle refreshes all known values from the cache, so a
    // channel that stops answering simply keeps its last good value until it
    // is marked dead by a NO DATA.
    for (final entry in _values.entries) {
      if (entry.value != null) _applyValue(entry.key, entry.value!);
    }

    // Speed-density needs RPM, MAP and IAT. If IAT is unavailable, refuse to
    // compute fuel rather than substituting a room-temperature guess: air
    // density at 30 C versus 60 C is a 12% error that would silently skew
    // every economy figure.
    final haveFuelInputs = _live.contains(ObdChannel.rpm) &&
        _live.contains(ObdChannel.map) &&
        _live.contains(ObdChannel.iat);

    double fuelFlow = 0.0;
    double economy = 0.0;
    if (haveFuelInputs) {
      fuelFlow = _calculator.calculateFuelFlowLh(
          rpm: _rpm, mapKpa: _map, iatC: _iat);
      economy =
          _calculator.calculateEconomyKml(speedKmh: _speed, fuelFlowLh: fuelFlow);
    }

    _telemetryController.add(TelemetryFrame(
      timestamp: DateTime.now(),
      rpm: _rpm,
      speedKmh: _speed,
      mapKpa: _map,
      ectC: _ect,
      iatC: _iat,
      tpsPercent: _tps,
      batteryVoltage: _volt,
      fuelFlowLh: fuelFlow,
      instantaneousKml: economy,
      leanAngleDeg: 0.0,
      gForce: 0.0,
      engineLoadPercent: _load,
      timingAdvanceDeg: _timing,
      fuelLevelPercent: _fuelLevel,
      ecuOdometerKm: _ecuOdo,
      live: Set.of(_live),
    ));
  }

  void disconnect() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _polling = false;
    _connection?.dispose();
    _connection = null;
    _lineParser.clear();
    _transcript.clear();
    for (final c in ObdChannel.values) {
      _values[c] = null;
    }
    _live.clear();
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete('');
      _pendingCompleter = null;
    }
    _setState(ObdConnectionState.disconnected);
  }
}