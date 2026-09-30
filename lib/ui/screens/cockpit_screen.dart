import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../../core/models/telemetry_data.dart';
import '../../core/bluetooth/obd_service.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/trip/trip_manager.dart';

class CockpitScreen extends StatefulWidget {
  final ObdService obdService;
  final SensorHub sensorHub;

  const CockpitScreen({
    super.key,
    required this.obdService,
    required this.sensorHub,
  });

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen> {
  TelemetryFrame _currentFrame = TelemetryFrame.empty();
  SensorHubData _currentSensor = SensorHubData.empty();
  String? _connectedDeviceName;

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

    widget.obdService.stateStream.listen((state) {
      if (mounted) setState(() {});
    });

    widget.sensorHub.dataStream.listen((sensorData) {
      if (mounted) {
        setState(() {
          _currentSensor = sensorData;
        });
      }

      // Feed data to TripManager if trip recording is active
      if (TripManager().isRecording) {
        TripManager().onTelemetryUpdate(
          sensorData: sensorData,
          obdFrame: widget.obdService.state == ObdConnectionState.connected
              ? _currentFrame
              : null,
        );
      }
    });

    TripManager().addListener(_onTripStateChanged);
  }

  void _onTripStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TripManager().removeListener(_onTripStateChanged);
    super.dispose();
  }

  void _toggleTripRecording() async {
    final tripMgr = TripManager();
    if (!tripMgr.isRecording) {
      tripMgr.startTrip();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF00FF66),
          content: Text('Trip Recording Dimulai! Pantau GPS, Speed & Lean Angle.'),
        ),
      );
    } else {
      final record = await tripMgr.stopTrip();
      if (!mounted || record == null) return;
      _showTripSummaryDialog(record);
    }
  }

  void _showTripSummaryDialog(TripRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.flag, color: Color(0xFF00FF66), size: 24),
            SizedBox(width: 8),
            Text(
              'RINGKASAN TRIP SELESAI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogRow('Jarak Tempuh', '${record.distanceKm.toStringAsFixed(2)} KM'),
            _buildDialogRow('Durasi', '${record.durationMin.toStringAsFixed(1)} Menit'),
            _buildDialogRow('Top Speed', '${record.maxSpeedKmh.toStringAsFixed(1)} KM/H'),
            _buildDialogRow('Rata-rata Speed', '${record.avgSpeedKmh.toStringAsFixed(1)} KM/H'),
            _buildDialogRow('Peak Rebah (Kiri/Kanan)',
                'L ${record.maxLeanLeftDeg.toStringAsFixed(0)}° / R ${record.maxLeanRightDeg.toStringAsFixed(0)}°'),
            _buildDialogRow('Rem Mendadak', '${record.hardBrakingCount} Kali'),
            _buildDialogRow('Estimasi Bensin', '${record.fuelConsumedL.toStringAsFixed(2)} L'),
            _buildDialogRow('Biaya BBM', 'Rp ${record.tripCostIdr.toStringAsFixed(0)}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.cloud_upload, color: Color(0xFF00E5FF), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Trip otomatis tersimpan ke Riwayat & di-sync ke Cloudflare PocketBase.',
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('TUTUP', style: TextStyle(color: Color(0xFF00E5FF))),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  void _showBluetoothPicker() async {
    try {
      final List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF131B2E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'PILIH DONGLE BLUETOOTH',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (devices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'Belum ada perangkat paired.\nPairing dulu dongle Kingbolen (OBDII) di Pengaturan Bluetooth HP (PIN: 1234).',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final dev = devices[index];
                          final bool isObd = (dev.name ?? '').toLowerCase().contains('obd');

                          return ListTile(
                            leading: Icon(
                              Icons.bluetooth,
                              color: isObd ? const Color(0xFF00FF66) : const Color(0xFF00E5FF),
                            ),
                            title: Text(
                              dev.name ?? 'Unknown Device',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isObd ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              dev.address,
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            trailing: isObd
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00FF66).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'RECOMMENDED',
                                      style: TextStyle(
                                        color: Color(0xFF00FF66),
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              _connectToDevice(dev);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal scan bluetooth: $e')),
      );
    }
  }

  void _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _connectedDeviceName = device.name ?? device.address;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Menghubungkan ke ${device.name}...')),
    );

    final success = await widget.obdService.connect(device.address);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF00FF66),
          content: Text('Berhasil terhubung ke ${device.name}! ECU Ready.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Koneksi gagal. Pastikan kontak PCX posisi ON.'),
        ),
      );
    }
  }

  String _getConnectionStatusText() {
    if (widget.obdService.isMockMode) return 'SIMULATOR ACTIVE';
    switch (widget.obdService.state) {
      case ObdConnectionState.connected:
        return _connectedDeviceName != null ? 'LIVE: $_connectedDeviceName' : 'OBD-2 CONNECTED';
      case ObdConnectionState.connecting:
        return 'CONNECTING...';
      case ObdConnectionState.handshaking:
        return 'INIT PROTOCOL (KWP)...';
      case ObdConnectionState.error:
        return 'CONNECTION ERROR';
      case ObdConnectionState.disconnected:
      default:
        return 'STANDALONE GPS MODE';
    }
  }

  Color _getConnectionColor() {
    if (widget.obdService.isMockMode) return const Color(0xFF00E5FF);
    switch (widget.obdService.state) {
      case ObdConnectionState.connected:
        return const Color(0xFF00FF66);
      case ObdConnectionState.connecting:
      case ObdConnectionState.handshaking:
        return const Color(0xFFFFB300);
      case ObdConnectionState.error:
        return Colors.redAccent;
      case ObdConnectionState.disconnected:
      default:
        return const Color(0xFF00E5FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isObdLive = widget.obdService.state == ObdConnectionState.connected ||
        widget.obdService.isMockMode;

    // Speed display: If OBD live, use ECU speed, else use smartphone GPS speed
    final double displaySpeed = isObdLive
        ? _currentFrame.speedKmh
        : _currentSensor.gpsSpeedKmh;

    final String speedUnit = isObdLive ? 'KM / H' : 'KM / H (GPS)';

    final tripMgr = TripManager();
    final bool isRecording = tripMgr.isRecording;

    final bool isOverheat = _currentFrame.ectC > 100.0;
    final bool isLowBatt = _currentFrame.batteryVoltage < 11.8;
    final connColor = _getConnectionColor();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Column(
            children: [
              // Top Status Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: _showBluetoothPicker,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: connColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getConnectionStatusText(),
                            style: TextStyle(
                              color: connColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.bluetooth_searching, color: Color(0xFF00E5FF), size: 20),
                        tooltip: 'Scan OBD Bluetooth',
                        onPressed: _showBluetoothPicker,
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.08),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                          style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Giant Speed Display
              Center(
                child: Column(
                  children: [
                    Text(
                      displaySpeed.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 84,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      speedUnit,
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Prominent Start/Stop Trip Bar
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRecording
                        ? Colors.redAccent.withOpacity(0.9)
                        : const Color(0xFF00FF66).withOpacity(0.9),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _toggleTripRecording,
                  icon: Icon(isRecording ? Icons.stop_circle : Icons.navigation),
                  label: Text(
                    isRecording
                        ? 'FINISH TRIP (${tripMgr.distanceKm.toStringAsFixed(1)} KM • ${_formatDuration(tripMgr.elapsed)})'
                        : 'START TRIP (STANDALONE GPS)',
                    style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 12),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // 2x2 Telemetry Grid (Glanceable Cards)
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.45,
                  children: [
                    // Card 1: Range or Trip Distance
                    _buildMetricCard(
                      title: isRecording ? 'JARAK TRIP INI' : 'SISA RANGE (DTE)',
                      value: isRecording
                          ? tripMgr.distanceKm.toStringAsFixed(1)
                          : '185',
                      unit: 'KM',
                      icon: isRecording ? Icons.route : Icons.local_gas_station,
                      accentColor: const Color(0xFF00FF66),
                    ),
                    // Card 2: MotoGP Lean Angle
                    _buildMetricCard(
                      title: 'LEAN ANGLE (MOTOGP)',
                      value: _currentSensor.rollAngleDeg.abs().toStringAsFixed(0),
                      unit: _currentSensor.rollAngleDeg < -2.0
                          ? '° LEFT'
                          : (_currentSensor.rollAngleDeg > 2.0 ? '° RIGHT' : '° CVR'),
                      icon: Icons.screen_rotation,
                      accentColor: const Color(0xFFFFB300),
                    ),
                    // Card 3: Radiator Temp or G-Force
                    _buildMetricCard(
                      title: isObdLive ? 'SUHU RADIATOR' : 'G-FORCE SENSOR',
                      value: isObdLive
                          ? _currentFrame.ectC.toStringAsFixed(0)
                          : '${_currentSensor.gForce >= 0 ? '+' : ''}${_currentSensor.gForce.toStringAsFixed(2)}',
                      unit: isObdLive ? '°C' : 'G',
                      icon: isObdLive ? Icons.thermostat : Icons.speed,
                      accentColor: isOverheat ? Colors.redAccent : const Color(0xFF00E5FF),
                      isAlert: isOverheat,
                    ),
                    // Card 4: Battery Voltage or Max Speed
                    _buildMetricCard(
                      title: isObdLive ? 'TEGANGAN AKI' : 'TOP SPEED RECORD',
                      value: isObdLive
                          ? _currentFrame.batteryVoltage.toStringAsFixed(1)
                          : tripMgr.maxSpeedKmh.toStringAsFixed(0),
                      unit: isObdLive ? 'VOLT' : 'KM/H',
                      icon: isObdLive ? Icons.battery_charging_full : Icons.military_tech,
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

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 10,
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
