import 'package:flutter/material.dart';
import '../../core/models/telemetry_data.dart';
import '../../core/bluetooth/obd_service.dart';

class CockpitScreen extends StatefulWidget {
  final ObdService obdService;
  const CockpitScreen({super.key, required this.obdService});

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen> {
  TelemetryFrame _currentFrame = TelemetryFrame.empty();

  @override
  void initState() {
    super.initState();
    widget.obdService.telemetryStream.listen((frame) {
      if (mounted) {
        setState(() {
          _currentFrame = frame;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isOverheat = _currentFrame.ectC > 100.0;
    final bool isLowBatt = _currentFrame.batteryVoltage < 11.8;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            children: [
              // Top Status Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: widget.obdService.state == ObdConnectionState.connected
                              ? const Color(0xFF00FF66)
                              : Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.obdService.isMockMode
                            ? 'SIMULATOR MODE'
                            : (widget.obdService.state == ObdConnectionState.connected
                                ? 'OBD-2 LIVE'
                                : 'DISCONNECTED'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.08),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    onPressed: () {
                      widget.obdService.enableMockMode(!widget.obdService.isMockMode);
                    },
                    icon: Icon(
                      widget.obdService.isMockMode ? Icons.cancel : Icons.play_arrow,
                      size: 16,
                      color: const Color(0xFF00E5FF),
                    ),
                    label: Text(
                      widget.obdService.isMockMode ? 'Stop Sim' : 'Start Sim',
                      style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Giant Speed Display
              Center(
                child: Column(
                  children: [
                    Text(
                      _currentFrame.speedKmh.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 84,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Text(
                      'KM / H',
                      style: TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3.0,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2x2 Telemetry Grid (Glanceable Cards)
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    _buildMetricCard(
                      title: 'SISA RANGE (DTE)',
                      value: '185',
                      unit: 'KM',
                      icon: Icons.local_gas_station,
                      accentColor: const Color(0xFF00FF66),
                    ),
                    _buildMetricCard(
                      title: 'EFISIENSI BBM',
                      value: _currentFrame.speedKmh > 2
                          ? _currentFrame.instantaneousKml.toStringAsFixed(1)
                          : _currentFrame.fuelFlowLh.toStringAsFixed(2),
                      unit: _currentFrame.speedKmh > 2 ? 'km / L' : 'L / jam',
                      icon: Icons.eco,
                      accentColor: const Color(0xFFFFB300),
                    ),
                    _buildMetricCard(
                      title: 'SUHU RADIATOR',
                      value: _currentFrame.ectC.toStringAsFixed(0),
                      unit: '°C',
                      icon: Icons.thermostat,
                      accentColor: isOverheat ? Colors.redAccent : const Color(0xFF00E5FF),
                      isAlert: isOverheat,
                    ),
                    _buildMetricCard(
                      title: 'TEGANGAN AKI',
                      value: _currentFrame.batteryVoltage.toStringAsFixed(1),
                      unit: 'VOLT',
                      icon: Icons.battery_charging_full,
                      accentColor: isLowBatt ? Colors.redAccent : const Color(0xFF7C4DFF),
                      isAlert: isLowBatt,
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

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color accentColor,
    bool isAlert = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAlert
            ? Colors.redAccent.withOpacity(0.15)
            : const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAlert ? Colors.redAccent : accentColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Icon(icon, size: 16, color: accentColor),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: isAlert ? Colors.redAccent : Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
