import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../models/telemetry_data.dart';
import '../telemetry/speed_density_calculator.dart';

enum ObdConnectionState { disconnected, connecting, handshaking, connected, error }

class ObdService {
  final SpeedDensityCalculator _calculator = const SpeedDensityCalculator();

  BluetoothConnection? _connection;
  ObdConnectionState _state = ObdConnectionState.disconnected;
  ObdConnectionState get state => _state;

  final StreamController<TelemetryFrame> _telemetryController =
      StreamController<TelemetryFrame>.broadcast();
  Stream<TelemetryFrame> get telemetryStream => _telemetryController.stream;

  final StreamController<ObdConnectionState> _stateController =
      StreamController<ObdConnectionState>.broadcast();
  Stream<ObdConnectionState> get stateStream => _stateController.stream;

  Timer? _pollingTimer;
  bool _isMockMode = false;
  bool get isMockMode => _isMockMode;

  // Running telemetry values
  double _currentRpm = 0.0;
  double _currentSpeed = 0.0;
  double _currentMap = 101.3;
  double _currentEct = 30.0;
  double _currentIat = 30.0;
  double _currentTps = 0.0;
  double _currentVolt = 12.5;

  // Serial buffer reader state
  final StringBuffer _rxBuffer = StringBuffer();
  Completer<String>? _pendingCommandCompleter;

  void enableMockMode(bool enable) {
    _isMockMode = enable;
    if (_isMockMode) {
      _startMockSimulation();
    } else {
      _pollingTimer?.cancel();
      _state = ObdConnectionState.disconnected;
      _stateController.add(_state);
    }
  }

  void _startMockSimulation() {
    _state = ObdConnectionState.connected;
    _stateController.add(_state);
    _pollingTimer?.cancel();

    double mockTps = 0.0;
    bool accelerating = true;

    _pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (accelerating) {
        mockTps += 2.0;
        if (mockTps >= 75.0) accelerating = false;
      } else {
        mockTps -= 1.5;
        if (mockTps <= 5.0) accelerating = true;
      }

      _currentTps = mockTps;
      _currentRpm = 1500.0 + (_currentTps * 95.0);
      _currentSpeed = (_currentRpm > 2200.0) ? (_currentRpm - 2200.0) / 75.0 : 0.0;
      _currentMap = 38.0 + (_currentTps * 0.7);
      _currentEct = 88.0 + (_currentTps * 0.05);
      _currentIat = 34.0;
      _currentVolt = 14.2;

      _emitTelemetryFrame();
    });
  }

  Future<bool> connect(String macAddress) async {
    if (_isMockMode) return true;

    try {
      _state = ObdConnectionState.connecting;
      _stateController.add(_state);

      _connection = await BluetoothConnection.toAddress(macAddress);

      // Listen to incoming serial stream
      _rxBuffer.clear();
      _connection!.input?.listen(
        _onDataReceived,
        onDone: () {
          disconnect();
        },
        onError: (e) {
          debugPrint('[ObdService] Serial input error: $e');
          disconnect();
        },
      );

      _state = ObdConnectionState.handshaking;
      _stateController.add(_state);

      // ELM327 Initialization Pipeline
      await _sendCommand('ATZ');
      await Future.delayed(const Duration(milliseconds: 600));
      await _sendCommand('ATE0'); // Echo Off
      await _sendCommand('ATL0'); // Linefeeds Off
      await _sendCommand('ATS0'); // Spaces Off
      await _sendCommand('ATSP5'); // Force ISO 14230-4 KWP (Fast Init)

      _state = ObdConnectionState.connected;
      _stateController.add(_state);

      _startRealPollingLoop();
      return true;
    } catch (e) {
      debugPrint('[ObdService] Connect error: $e');
      _state = ObdConnectionState.error;
      _stateController.add(_state);
      disconnect();
      return false;
    }
  }

  void _onDataReceived(Uint8List data) {
    final str = ascii.decode(data, allowInvalid: true);
    for (int i = 0; i < str.length; i++) {
      final char = str[i];
      if (char == '>') {
        // ELM327 command prompt reached, resolve pending command
        final response = _rxBuffer.toString().trim();
        _rxBuffer.clear();
        if (_pendingCommandCompleter != null &&
            !_pendingCommandCompleter!.isCompleted) {
          _pendingCommandCompleter!.complete(response);
          _pendingCommandCompleter = null;
        }
      } else if (char != '\r' && char != '\n') {
        _rxBuffer.write(char);
      }
    }
  }

  Future<String> _sendCommand(String cmd,
      {Duration timeout = const Duration(milliseconds: 1200)}) async {
    if (_connection == null || !_connection!.isConnected) return '';

    _pendingCommandCompleter = Completer<String>();
    try {
      _connection!.output.add(Uint8List.fromList(ascii.encode('$cmd\r')));
      await _connection!.output.allSent;
      return await _pendingCommandCompleter!.future.timeout(timeout,
          onTimeout: () {
        debugPrint('[ObdService] Command $cmd timed out');
        return '';
      });
    } catch (e) {
      debugPrint('[ObdService] Send command error: $e');
      return '';
    }
  }

  void _startRealPollingLoop() {
    _pollingTimer?.cancel();
    int cycle = 0;

    _pollingTimer =
        Timer.periodic(const Duration(milliseconds: 70), (timer) async {
      if (_state != ObdConnectionState.connected) return;

      try {
        switch (cycle % 6) {
          case 0: // RPM
            final res = await _sendCommand('010C');
            _parseRpm(res);
            break;
          case 1: // Speed
            final res = await _sendCommand('010D');
            _parseSpeed(res);
            break;
          case 2: // MAP
            final res = await _sendCommand('010B');
            _parseMap(res);
            break;
          case 3: // TPS
            final res = await _sendCommand('0111');
            _parseTps(res);
            break;
          case 4: // ECT
            final res = await _sendCommand('0105');
            _parseEct(res);
            break;
          case 5: // Battery Voltage
            final res = await _sendCommand('ATRV');
            _parseVolt(res);
            break;
        }
        cycle++;
        _emitTelemetryFrame();
      } catch (e) {
        debugPrint('[ObdService] Polling exception: $e');
      }
    });
  }

  void _parseRpm(String raw) {
    // Expected response format: "410CXXXX" where XXXX is hex bytes A and B
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('410C');
    if (idx != -1 && clean.length >= idx + 8) {
      final hexA = clean.substring(idx + 4, idx + 6);
      final hexB = clean.substring(idx + 6, idx + 8);
      final intA = int.tryParse(hexA, radix: 16) ?? 0;
      final intB = int.tryParse(hexB, radix: 16) ?? 0;
      _currentRpm = ((intA * 256.0) + intB) / 4.0;
    }
  }

  void _parseSpeed(String raw) {
    // Expected response format: "410DXX"
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('410D');
    if (idx != -1 && clean.length >= idx + 6) {
      final hex = clean.substring(idx + 4, idx + 6);
      _currentSpeed = (int.tryParse(hex, radix: 16) ?? 0).toDouble();
    }
  }

  void _parseMap(String raw) {
    // Expected response format: "410BXX" (Pressure in kPa)
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('410B');
    if (idx != -1 && clean.length >= idx + 6) {
      final hex = clean.substring(idx + 4, idx + 6);
      _currentMap = (int.tryParse(hex, radix: 16) ?? 101).toDouble();
    }
  }

  void _parseTps(String raw) {
    // Expected response format: "4111XX" (Throttle % = A * 100 / 255)
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('4111');
    if (idx != -1 && clean.length >= idx + 6) {
      final hex = clean.substring(idx + 4, idx + 6);
      final val = int.tryParse(hex, radix: 16) ?? 0;
      _currentTps = (val * 100.0) / 255.0;
    }
  }

  void _parseEct(String raw) {
    // Expected response format: "4105XX" (Coolant Temp °C = A - 40)
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('4105');
    if (idx != -1 && clean.length >= idx + 6) {
      final hex = clean.substring(idx + 4, idx + 6);
      final val = int.tryParse(hex, radix: 16) ?? 40;
      _currentEct = (val - 40).toDouble();
    }
  }

  void _parseVolt(String raw) {
    // Expected response format: "14.2V" or "12.5V"
    final clean = raw.replaceAll(' ', '').toUpperCase().replaceAll('V', '');
    final volt = double.tryParse(clean);
    if (volt != null && volt > 5.0 && volt < 20.0) {
      _currentVolt = volt;
    }
  }

  void _emitTelemetryFrame() {
    final fuelFlow = _calculator.calculateFuelFlowLh(
      rpm: _currentRpm,
      mapKpa: _currentMap,
      iatC: _currentIat,
    );

    final economy = _calculator.calculateEconomyKml(
      speedKmh: _currentSpeed,
      fuelFlowLh: fuelFlow,
    );

    final frame = TelemetryFrame(
      timestamp: DateTime.now(),
      rpm: _currentRpm,
      speedKmh: _currentSpeed,
      mapKpa: _currentMap,
      ectC: _currentEct,
      iatC: _currentIat,
      tpsPercent: _currentTps,
      batteryVoltage: _currentVolt,
      fuelFlowLh: fuelFlow,
      instantaneousKml: economy,
      leanAngleDeg: 0.0,
      gForce: 0.0,
    );

    _telemetryController.add(frame);
  }

  void disconnect() {
    _pollingTimer?.cancel();
    _connection?.dispose();
    _connection = null;
    _rxBuffer.clear();
    if (_pendingCommandCompleter != null &&
        !_pendingCommandCompleter!.isCompleted) {
      _pendingCommandCompleter!.complete('');
      _pendingCommandCompleter = null;
    }
    _state = ObdConnectionState.disconnected;
    _stateController.add(_state);
  }
}
