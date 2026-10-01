import 'package:flutter/material.dart';
import '../../core/bluetooth/obd_service.dart';
import '../../core/models/telemetry_data.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/telemetry/lean_estimator.dart';
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Using FittedBox with a standard 16:9 base canvas (320x180)
            // guarantees ZERO render overflows on any Android PiP window dimension
            return Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: Container(
                  width: 320,
                  height: 180,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E17),
                    border: Border.all(
                      color: isOverheat ? Colors.redAccent : const Color(0xFF00E5FF).withOpacity(0.5),
                      width: 2.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Left: Giant Speedometer
                      Expanded(
                        flex: 48,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              displaySpeed.toStringAsFixed(0),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 68,
                                fontWeight: FontWeight.w900,
                                height: 0.9,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isObdLive ? 'KM / H' : 'KM / H (GPS)',
                              style: const TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Divider Line
                      Container(
                        width: 2,
                        height: 120,
                        color: Colors.white12,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),

                      // Right: 4 Metrics Stack
                      Expanded(
                        flex: 52,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPipMetric(
                              label: tripMgr.isRecording ? 'JARAK' : 'RANGE',
                              value: tripMgr.isRecording
                                  ? '${tripMgr.distanceKm.toStringAsFixed(1)} KM'
                                  : '185 KM',
                              color: const Color(0xFF00FF66),
                            ),
                            _buildPipMetric(
                              label: 'BBM',
                              value: _currentFrame.speedKmh > 2
                                  ? '${_currentFrame.instantaneousKml.toStringAsFixed(1)} km/L'
                                  : '46.5 km/L',
                              color: const Color(0xFFFFB300),
                            ),
                            _buildPipMetric(
                              label: 'SUHU',
                              // Honesty rule: no placeholder when the ECU is
                              // silent. This used to print a hardcoded 88°C,
                              // which reads as a real overheat warning.
                              value: isObdLive
                                  ? '${_currentFrame.ectC.toStringAsFixed(0)}°C'
                                  : '--',
                              color: isObdLive
                                  ? (isOverheat
                                      ? Colors.redAccent
                                      : const Color(0xFF00E5FF))
                                  : Colors.white24,
                            ),
                            _buildPipMetric(
                              label: 'REBAH',
                              // A trailing marker flags that the two lean
                              // sources disagree, so the rider knows the number
                              // is not to be trusted. The PiP is too small for
                              // both figures; the cockpit gauge shows them.
                              value:
                                  '${_currentSensor.rollAngleDeg.abs().toStringAsFixed(0)}° ${_currentSensor.rollAngleDeg < -1.5 ? 'L' : (_currentSensor.rollAngleDeg > 1.5 ? 'R' : 'CVR')}'
                                  '${_currentSensor.lean.confidence == LeanConfidence.degraded ? ' *' : ''}',
                              color: _currentSensor.lean.confidence ==
                                      LeanConfidence.degraded
                                  ? Colors.redAccent
                                  : const Color(0xFF7C4DFF),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPipMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
