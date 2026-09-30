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

  // Running telemetry buffers
  double _currentRpm = 0.0;
  double _currentSpeed = 0.0;
  double _currentMap = 101.3;
  double _currentEct = 30.0;
  double _currentIat = 30.0;
  double _currentTps = 0.0;
  double _currentVolt = 12.5;

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
      _state = ObdConnectionState.handshaking;
      _stateController.add(_state);

      // Execute ELM327 initialization commands
      await _sendCommand('ATZ');
      await Future.delayed(const Duration(milliseconds: 500));
      await _sendCommand('ATE0');
      await _sendCommand('ATL0');
      await _sendCommand('ATS0');
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

  void _startRealPollingLoop() {
    _pollingTimer?.cancel();
    int cycle = 0;

    _pollingTimer = Timer.periodic(const Duration(milliseconds: 65), (timer) async {
      if (_state != ObdConnectionState.connected) return;

      try {
        switch (cycle % 6) {
          case 0:
            final res = await _sendCommand('010C'); // RPM
            _parseRpm(res);
            break;
          case 1:
            final res = await _sendCommand('010D'); // Speed
            _parseSpeed(res);
            break;
          case 2:
            final res = await _sendCommand('010B'); // MAP
            _parseMap(res);
            break;
          case 3:
            final res = await _sendCommand('0111'); // TPS
            _parseTps(res);
            break;
          case 4:
            final res = await _sendCommand('0105'); // ECT
            _parseEct(res);
            break;
          case 5:
            final res = await _sendCommand('ATRV'); // Voltage
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

  Future<String> _sendCommand(String cmd) async {
    if (_connection == null || !_connection!.isConnected) return '';
    try {
      _connection!.output.add(Uint8List.fromList(utf8.encode('$cmd\r')));
      await _connection!.output.allSent;
      // In production, buffer read response until '>' prompt
      return '';
    } catch (e) {
      return '';
    }
  }

  void _parseRpm(String raw) {
    // Expected 41 0C A B -> ((A*256)+B)/4
  }

  void _parseSpeed(String raw) {
    // Expected 41 0D A -> A
  }

  void _parseMap(String raw) {
    // Expected 41 0B A -> A
  }

  void _parseTps(String raw) {
    // Expected 41 11 A -> (A*100)/255
  }

  void _parseEct(String raw) {
    // Expected 41 05 A -> A-40
  }

  void _parseVolt(String raw) {
    // Expected 14.2V ASCII
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
    _state = ObdConnectionState.disconnected;
    _stateController.add(_state);
  }
}
