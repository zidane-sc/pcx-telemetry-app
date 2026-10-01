import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../models/telemetry_data.dart';
import '../models/vehicle_profile.dart';
import '../telemetry/speed_density_calculator.dart';

enum ObdConnectionState {
  disconnected,
  connecting,
  handshaking,
  connected,
  error,
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

  BluetoothConnection? _connection;
  final SpeedDensityCalculator _calculator = const SpeedDensityCalculator();

  bool _isMockMode = false;
  bool get isMockMode => _isMockMode;
  Timer? _mockTimer;
  Timer? _pollingTimer;

  final StringBuffer _rxBuffer = StringBuffer();
  Completer<String>? _pendingCommandCompleter;

  // Real ECU Telemetry State
  double _currentRpm = 0.0;
  double _currentSpeed = 0.0;
  double _currentMap = 101.3;
  double _currentTps = 0.0;
  double _currentEct = 30.0;
  double _currentIat = 30.0;
  double _currentVolt = 12.5;
  double _currentEngineLoad = 0.0;
  double _currentTimingAdvance = 10.0;
  double _currentFuelLevel = 0.0;
  double _currentEcuOdo = 0.0;

  void enableMockMode(bool enable) {
    _isMockMode = enable;
    if (_isMockMode) {
      _startMockSimulation();
      _state = ObdConnectionState.connected;
      _stateController.add(_state);
    } else {
      _mockTimer?.cancel();
      _state = ObdConnectionState.disconnected;
      _stateController.add(_state);
    }
  }

  void _startMockSimulation() {
    _mockTimer?.cancel();
    double mockTps = 0.0;
    bool throttleOpening = true;

    _mockTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isMockMode) return;

      if (throttleOpening) {
        mockTps += 2.5;
        if (mockTps >= 65.0) throttleOpening = false;
      } else {
        mockTps -= 1.8;
        if (mockTps <= 0.0) {
          mockTps = 0.0;
          throttleOpening = true;
        }
      }

      _currentTps = mockTps;
      _currentRpm = 1500.0 + (_currentTps * 95.0);
      _currentSpeed = (_currentRpm > 2200.0) ? (_currentRpm - 2200.0) / 75.0 : 0.0;
      _currentMap = 38.0 + (_currentTps * 0.7);
      _currentEct = 88.0 + (_currentTps * 0.05);
      _currentIat = 34.0;
      _currentVolt = 14.2;
      _currentEngineLoad = (mockTps * 1.2).clamp(12.0, 95.0);
      _currentTimingAdvance = 12.0 + (_currentRpm / 400.0);
      _currentFuelLevel = 75.0;

      _emitTelemetryFrame();
    });
  }

  Future<bool> connect(String macAddress, {ObdProtocolType protocol = ObdProtocolType.kwp2000Fast}) async {
    if (_isMockMode) return true;

    try {
      _state = ObdConnectionState.connecting;
      _stateController.add(_state);

      _connection = await BluetoothConnection.toAddress(macAddress);

      // Listen to incoming serial stream
      _rxBuffer.clear();
      _connection!.input?.listen(
        _onDataReceived,
        onDone: () => disconnect(),
        onError: (e) {
          debugPrint('[ObdService] Serial input error: $e');
          disconnect();
        },
      );

      _state = ObdConnectionState.handshaking;
      _stateController.add(_state);

      // ELM327 Adaptive Initialization Pipeline
      await _sendCommand('ATZ');
      await Future.delayed(const Duration(milliseconds: 600));
      await _sendCommand('ATE0'); // Echo Off
      await _sendCommand('ATL0'); // Linefeeds Off
      await _sendCommand('ATS0'); // Spaces Off
      // Set protocol based on active vehicle (KWP2000 for PCX, CAN for Yaris/cars)
      await _sendCommand('ATSP${protocol.atspValue}');

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
        switch (cycle % 9) {
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
          case 4: // Engine Load
            final res = await _sendCommand('0104');
            _parseEngineLoad(res);
            break;
          case 5: // Timing Advance
            final res = await _sendCommand('010E');
            _parseTimingAdvance(res);
            break;
          case 6: // ECT (Coolant)
            final res = await _sendCommand('0105');
            _parseEct(res);
            break;
          case 7: // Battery Voltage
            final res = await _sendCommand('ATRV');
            _parseVolt(res);
            break;
          case 8: // Odometer (if supported) or Fuel Level
            final resOdo = await _sendCommand('01A6');
            _parseOdometer(resOdo);
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
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('410D');
    if (idx != -1 && clean.length >= idx + 6) {
      final hex = clean.substring(idx + 4, idx + 6);
      _currentSpeed = (int.tryParse(hex, radix: 16) ?? 0).toDouble();
    }
  }

  void _parseMap(String raw) {
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('410B');
    if (idx != -1 && clean.length >= idx + 6) {
      final hex = clean.substring(idx + 4, idx + 6);
      _currentMap = (int.tryParse(hex, radix: 16) ?? 101).toDouble();
    }
  }

  void _parseTps(String raw) {
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('4111');
    if (idx != -1 && clean.length >= idx + 6) {
      final hex = clean.substring(idx + 4, idx + 6);
      final val = int.tryParse(hex, radix: 16) ?? 0;
      _currentTps = (val * 100.0) / 255.0;
    }
  }

  void _parseEngineLoad(String raw) {
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('4104');
    if (idx != -1 && clean.length >= idx + 6) {
      final hex = clean.substring(idx + 4, idx + 6);
      final val = int.tryParse(hex, radix: 16) ?? 0;
      _currentEngineLoad = (val * 100.0) / 255.0;
    }
  }

  void _parseTimingAdvance(String raw) {
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('410E');
    if (idx != -1 && clean.length >= idx + 6) {
      final hex = clean.substring(idx + 4, idx + 6);
      final val = int.tryParse(hex, radix: 16) ?? 128;
      _currentTimingAdvance = (val - 128) / 2.0;
    }
  }

  void _parseEct(String raw) {
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('4105');
    if (idx != -1 && clean.length >= idx + 6) {
      final hex = clean.substring(idx + 4, idx + 6);
      final val = int.tryParse(hex, radix: 16) ?? 40;
      _currentEct = (val - 40).toDouble();
    }
  }

  void _parseVolt(String raw) {
    final clean = raw.replaceAll(' ', '').toUpperCase().replaceAll('V', '');
    final volt = double.tryParse(clean);
    if (volt != null && volt > 5.0 && volt < 20.0) {
      _currentVolt = volt;
    }
  }

  void _parseOdometer(String raw) {
    final clean = raw.replaceAll(' ', '').toUpperCase();
    final idx = clean.indexOf('41A6');
    if (idx != -1 && clean.length >= idx + 12) {
      final hex = clean.substring(idx + 4, idx + 12);
      final val = int.tryParse(hex, radix: 16);
      if (val != null && val > 0) {
        _currentEcuOdo = val / 10.0;
      }
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
      engineLoadPercent: _currentEngineLoad,
      timingAdvanceDeg: _currentTimingAdvance,
      fuelLevelPercent: _currentFuelLevel,
      ecuOdometerKm: _currentEcuOdo,
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
