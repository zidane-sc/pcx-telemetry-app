import 'package:flutter/material.dart';
import '../../core/bluetooth/obd_service.dart';
import '../../core/models/telemetry_data.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/trip/trip_manager.dart';

class MiniPipCockpit extends StatefulWidget {
  final ObdService obdService;
  final SensorHub sensorHub;

  const MiniPipCockpit({
    super.key,
    required this.obdService,
    required this.sensorHub,
  });

  @override
  State<MiniPipCockpit> createState() => _MiniPipCockpitState();
}

class _MiniPipCockpitState extends State<MiniPipCockpit> {
  TelemetryFrame _currentFrame = TelemetryFrame.empty();
  SensorHubData _currentSensor = SensorHubData.empty();

  @override
  void initState() {
    super.initState();
    widget.obdService.telemetryStream.listen((frame) {
      if (mounted) setState(() => _currentFrame = frame);
    });

    widget.sensorHub.dataStream.listen((sensorData) {
      if (mounted) setState(() => _currentSensor = sensorData);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isObdLive =
        widget.obdService.state == ObdConnectionState.connected ||
            widget.obdService.isMockMode;

    final double displaySpeed =
        isObdLive ? _currentFrame.speedKmh : _currentSensor.gpsSpeedKmh;

    final tripMgr = TripManager();
    final bool isOverheat = _currentFrame.ectC > 100.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: const Color(0xFF0A0E17),
          child: Row(
            children: [
              // Left: Speed Display
              Expanded(
                flex: 40,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      displaySpeed.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 0.9,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Text(
                      'KM/H',
                      style: TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                width: 1,
                height: 50,
                color: Colors.white12,
                margin: const EdgeInsets.symmetric(horizontal: 6),
              ),

              // Right: 4 Glanceable Key Metrics
              Expanded(
                flex: 60,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildPipPill(
                          label: 'DTE',
                          value: tripMgr.isRecording
                              ? '${tripMgr.distanceKm.toStringAsFixed(1)} KM'
                              : '185 KM',
                          color: const Color(0xFF00FF66),
                        ),
                        _buildPipPill(
                          label: 'BBM',
                          value: _currentFrame.speedKmh > 2
                              ? '${_currentFrame.instantaneousKml.toStringAsFixed(0)} km/L'
                              : '46 km/L',
                          color: const Color(0xFFFFB300),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildPipPill(
                          label: 'ECT',
                          value: '${_currentFrame.ectC.toStringAsFixed(0)}°C',
                          color: isOverheat
                              ? Colors.redAccent
                              : const Color(0xFF00E5FF),
                        ),
                        _buildPipPill(
                          label: 'LEAN',
                          value:
                              '${_currentSensor.rollAngleDeg.abs().toStringAsFixed(0)}° ${_currentSensor.rollAngleDeg < -2 ? 'L' : (_currentSensor.rollAngleDeg > 2 ? 'R' : '')}',
                          color: const Color(0xFF7C4DFF),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPipPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
