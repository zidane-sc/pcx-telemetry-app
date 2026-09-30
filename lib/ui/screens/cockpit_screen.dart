import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/models/telemetry_data.dart';
import '../../core/bluetooth/obd_service.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/trip/trip_manager.dart';
import '../../core/sync/pocketbase_service.dart';
import '../../core/pip/pip_manager.dart';
import '../../core/audio/voice_alert_service.dart';

class CockpitScreen extends StatefulWidget {
  final ObdService obdService;
  final SensorHub sensorHub;
  final PocketBaseService pbService;

  const CockpitScreen({
    super.key,
    required this.obdService,
    required this.sensorHub,
    required this.pbService,
  });

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen> {
  TelemetryFrame _currentFrame = TelemetryFrame.empty();
  SensorHubData _currentSensor = SensorHubData.empty();
  String? _connectedDeviceName;

  // Auto-Start Trip Countdown State
  bool _isAutoStartDialogShowing = false;
  DateTime? _autoStartCooldownUntil;
  Timer? _countdownTimer;
  int _countdownSeconds = 5;

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

      // Check auto-start trip trigger when vehicle starts moving
      _checkAutoStartTrigger(sensorData.gpsSpeedKmh);

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
    _countdownTimer?.cancel();
    TripManager().removeListener(_onTripStateChanged);
    super.dispose();
  }

  void _checkAutoStartTrigger(double speedKmh) {
    if (TripManager().isRecording) return;
    if (_isAutoStartDialogShowing) return;
    if (_autoStartCooldownUntil != null &&
        DateTime.now().isBefore(_autoStartCooldownUntil!)) {
      return;
    }

    // Trigger auto-start if moving > 14 km/h
    if (speedKmh > 14.0) {
      _triggerAutoStartCountdown(speedKmh);
    }
  }

  void _triggerAutoStartCountdown(double speedKmh) {
    _isAutoStartDialogShowing = true;
    _countdownSeconds = 5;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _countdownTimer?.cancel();
            _countdownTimer =
                Timer.periodic(const Duration(seconds: 1), (timer) {
              if (_countdownSeconds > 1) {
                setDialogState(() {
                  _countdownSeconds--;
                });
              } else {
                timer.cancel();
                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                _isAutoStartDialogShowing = false;
                _toggleTripRecording();
                VoiceAlertService().speakAlert("Trip otomatis dimulai!");
              }
            });

            return AlertDialog(
              backgroundColor: const Color(0xFF131B2E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: const [
                  Icon(Icons.directions_bike,
                      color: Color(0xFF00FF66), size: 28),
                  SizedBox(width: 10),
                  Text(
                    'GERAKAN TERDETEKSI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Kecepatan ${speedKmh.toStringAsFixed(0)} km/h terdeteksi.\nMemulai rekam trip dalam:',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(
                          value: _countdownSeconds / 5.0,
                          strokeWidth: 5,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF00FF66)),
                          backgroundColor: Colors.white10,
                        ),
                      ),
                      Text(
                        '$_countdownSeconds',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.15),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      _countdownTimer?.cancel();
                      Navigator.pop(ctx);
                      _isAutoStartDialogShowing = false;
                      _autoStartCooldownUntil =
                          DateTime.now().add(const Duration(seconds: 90));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Auto-start trip dibatalkan (jeda 90 detik).')),
                      );
                    },
                    child: const Text(
                      'BATALKAN (BUKAN RIDING)',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _countdownTimer?.cancel();
      _isAutoStartDialogShowing = false;
    });
  }

  void _toggleTripRecording() async {
    final tripMgr = TripManager();
    if (!tripMgr.isRecording) {
      tripMgr.startTrip();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF00FF66),
          content:
              Text('Trip Recording Dimulai! Pantau GPS, Speed & Lean Angle.'),
        ),
      );
    } else {
      final record = await tripMgr.stopTrip();
      if (!mounted || record == null) return;
      _showTripSummaryDialog(record);
    }
  }

  void _enterPipMode() async {
    final pipMgr = PipManager();
    final available = await pipMgr.isPipAvailable;
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orangeAccent,
          content:
              Text('Mode Picture-in-Picture (PiP) tidak didukung pada HP ini.'),
        ),
      );
      return;
    }

    final success = await pipMgr.enablePip();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Gagal mengaktifkan mode PiP.'),
        ),
      );
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
            _buildDialogRow(
                'Jarak Tempuh', '${record.distanceKm.toStringAsFixed(2)} KM'),
            _buildDialogRow(
                'Durasi', '${record.durationMin.toStringAsFixed(1)} Menit'),
            _buildDialogRow(
                'Top Speed', '${record.maxSpeedKmh.toStringAsFixed(1)} KM/H'),
            _buildDialogRow('Rata-rata Speed',
                '${record.avgSpeedKmh.toStringAsFixed(1)} KM/H'),
            _buildDialogRow('Peak Rebah (Kiri/Kanan)',
                'L ${record.maxLeanLeftDeg.toStringAsFixed(0)}° / R ${record.maxLeanRightDeg.toStringAsFixed(0)}°'),
            _buildDialogRow('Rem Mendadak', '${record.hardBrakingCount} Kali'),
            _buildDialogRow(
                'Estimasi Bensin', '${record.fuelConsumedL.toStringAsFixed(2)} L'),
            _buildDialogRow(
                'Biaya BBM', 'Rp ${record.tripCostIdr.toStringAsFixed(0)}'),
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
            child:
                const Text('TUTUP', style: TextStyle(color: Color(0xFF00E5FF))),
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
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ],
      ),
    );
  }

  void _showBluetoothPicker() async {
    try {
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ].request();

      if (statuses[Permission.bluetoothConnect] ==
          PermissionStatus.permanentlyDenied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: const Text(
                'Izin Bluetooth ditolak permanen. Buka Pengaturan HP untuk mengizinkan.'),
            action: SnackBarAction(
              label: 'PENGATURAN',
              textColor: Colors.white,
              onPressed: () => openAppSettings(),
            ),
          ),
        );
        return;
      }

      if (statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orangeAccent,
            content:
                Text('Izin Bluetooth Connect dibutuhkan untuk scan perangkat.'),
          ),
        );
        return;
      }

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
                        icon: const Icon(Icons.close,
                            color: Colors.white54, size: 20),
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
                          final bool isObd =
                              (dev.name ?? '').toLowerCase().contains('obd');

                          return ListTile(
                            leading: Icon(
                              Icons.bluetooth,
                              color: isObd
                                  ? const Color(0xFF00FF66)
                                  : const Color(0xFF00E5FF),
                            ),
                            title: Text(
                              dev.name ?? 'Unknown Device',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight:
                                    isObd ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              dev.address,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11),
                            ),
                            trailing: isObd
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00FF66)
                                          .withOpacity(0.2),
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
        return _connectedDeviceName != null
            ? 'LIVE: $_connectedDeviceName'
            : 'OBD-2 CONNECTED';
      case ObdConnectionState.connecting:
        return 'CONNECTING...';
      case ObdConnectionState.handshaking:
        return 'INIT PROTOCOL (KWP)...';
      case ObdConnectionState.error:
        return 'CONNECTION ERROR';
      case ObdConnectionState.disconnected:
      default:
        return 'STANDALONE GPS';
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            if (orientation == Orientation.landscape) {
              return _buildLandscapeLayout();
            }
            return _buildPortraitLayout();
          },
        ),
      ),
    );
  }

  Widget _buildPortraitLayout() {
    final bool isObdLive =
        widget.obdService.state == ObdConnectionState.connected ||
            widget.obdService.isMockMode;

    final double displaySpeed =
        isObdLive ? _currentFrame.speedKmh : _currentSensor.gpsSpeedKmh;

    final String speedUnit = isObdLive ? 'KM / H' : 'KM / H (GPS)';
    final tripMgr = TripManager();
    final bool isRecording = tripMgr.isRecording;
    final bool isOverheat = isObdLive && _currentFrame.ectC > 100.0;
    final bool isLowBatt = isObdLive && _currentFrame.batteryVoltage < 11.8;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      child: Column(
        children: [
          _buildTopStatusBar(),
          const SizedBox(height: 6),

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

          const SizedBox(height: 10),
          _buildTripButton(isRecording, tripMgr),
          const SizedBox(height: 12),

          // 2x2 Telemetry Grid
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: _buildMetricCards(
                  isRecording, isObdLive, tripMgr, isOverheat, isLowBatt),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    final bool isObdLive =
        widget.obdService.state == ObdConnectionState.connected ||
            widget.obdService.isMockMode;

    final double displaySpeed =
        isObdLive ? _currentFrame.speedKmh : _currentSensor.gpsSpeedKmh;

    final String speedUnit = isObdLive ? 'KM / H' : 'KM / H (GPS)';
    final tripMgr = TripManager();
    final bool isRecording = tripMgr.isRecording;
    final bool isOverheat = isObdLive && _currentFrame.ectC > 100.0;
    final bool isLowBatt = isObdLive && _currentFrame.batteryVoltage < 11.8;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
      child: Row(
        children: [
          // Left Pane: Big Speedometer + Start/Stop Button (42% width)
          Expanded(
            flex: 42,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  displaySpeed.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 76,
                    fontWeight: FontWeight.w900,
                    height: 0.95,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  speedUnit,
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRecording
                          ? Colors.redAccent.withOpacity(0.9)
                          : const Color(0xFF00FF66).withOpacity(0.9),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _toggleTripRecording,
                    icon: Icon(
                        isRecording ? Icons.stop_circle : Icons.navigation,
                        size: 16),
                    label: Text(
                      isRecording
                          ? 'FINISH (${tripMgr.distanceKm.toStringAsFixed(1)} KM)'
                          : 'START TRIP',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Right Pane: Top Status Bar + 2x2 Compact Grid (58% width)
          Expanded(
            flex: 58,
            child: Column(
              children: [
                _buildTopStatusBar(),
                const SizedBox(height: 6),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 2.0,
                    children: _buildMetricCards(
                        isRecording, isObdLive, tripMgr, isOverheat, isLowBatt),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopStatusBar() {
    final connColor = _getConnectionColor();
    return Row(
      children: [
        // Left Connection Pill (wrapped in Expanded so it never overflows)
        Expanded(
          child: InkWell(
            onTap: _showBluetoothPicker,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: connColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      _getConnectionStatusText(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: connColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down,
                      color: Colors.white54, size: 16),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 4),

        // Right Action Controls
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cloud Sync Indicator
            ValueListenableBuilder<bool>(
              valueListenable: widget.pbService.isConnectedNotifier,
              builder: (context, isConnected, _) {
                return InkWell(
                  onTap: () {
                    widget.pbService.autoLogin();
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? const Color(0xFF00FF66).withOpacity(0.12)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isConnected
                            ? const Color(0xFF00FF66).withOpacity(0.4)
                            : Colors.white12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_done,
                          size: 10,
                          color: isConnected
                              ? const Color(0xFF00FF66)
                              : Colors.white38,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isConnected ? 'SYNC' : 'OFF',
                          style: TextStyle(
                            color: isConnected
                                ? const Color(0xFF00FF66)
                                : Colors.white38,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),

            // Native PiP Button (Floating over Google Maps)
            IconButton(
              icon: const Icon(
                Icons.picture_in_picture_alt,
                color: Color(0xFF00E5FF),
                size: 16,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Floating PiP HUD (Di atas Google Maps)',
              onPressed: _enterPipMode,
            ),
            const SizedBox(width: 2),

            // Bluetooth Scan Button
            IconButton(
              icon: const Icon(Icons.bluetooth_searching,
                  color: Color(0xFF00E5FF), size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Scan OBD Bluetooth',
              onPressed: _showBluetoothPicker,
            ),
            const SizedBox(width: 4),

            // Simulation Toggle Pill
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.08),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: const Size(36, 22),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                widget.obdService.enableMockMode(!widget.obdService.isMockMode);
              },
              child: Text(
                widget.obdService.isMockMode ? 'Stop' : 'Sim',
                style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTripButton(bool isRecording, TripManager tripMgr) {
    return SizedBox(
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
          style: const TextStyle(
              fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 12),
        ),
      ),
    );
  }

  List<Widget> _buildMetricCards(bool isRecording, bool isObdLive,
      TripManager tripMgr, bool isOverheat, bool isLowBatt) {
    return [
      // Card 1: Range or Trip Distance
      _buildMetricCard(
        title: isRecording ? 'JARAK TRIP INI' : 'SISA RANGE (DTE)',
        value: isRecording
            ? tripMgr.distanceKm.toStringAsFixed(1)
            : (isObdLive ? '185' : '--'),
        unit: isRecording ? 'KM' : (isObdLive ? 'KM' : 'BUTUH OBD'),
        icon: isRecording ? Icons.route : Icons.local_gas_station,
        accentColor: const Color(0xFF00FF66),
      ),
      // Card 2: MotoGP Lean Angle
      _buildMetricCard(
        title: 'LEAN ANGLE (MOTOGP)',
        value: _currentSensor.rollAngleDeg.abs().toStringAsFixed(0),
        unit: _currentSensor.rollAngleDeg < -1.5
            ? '° LEFT'
            : (_currentSensor.rollAngleDeg > 1.5 ? '° RIGHT' : '° CVR'),
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
      // Card 4: Battery Voltage or Top Speed
      _buildMetricCard(
        title: isObdLive ? 'TEGANGAN AKI' : 'TOP SPEED RECORD',
        value: isObdLive
            ? _currentFrame.batteryVoltage.toStringAsFixed(1)
            : (tripMgr.maxSpeedKmh > 0
                ? tripMgr.maxSpeedKmh.toStringAsFixed(0)
                : '--'),
        unit: isObdLive ? 'VOLT' : 'KM/H',
        icon: isObdLive ? Icons.battery_charging_full : Icons.military_tech,
        accentColor: isLowBatt ? Colors.redAccent : const Color(0xFF7C4DFF),
        isAlert: isLowBatt,
      ),
    ];
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isAlert
            ? Colors.redAccent.withOpacity(0.15)
            : const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAlert ? Colors.redAccent : accentColor.withOpacity(0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Icon(icon, size: 14, color: accentColor),
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
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 9,
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
