import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/models/telemetry_data.dart';
import '../../core/bluetooth/obd_service.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/trip/trip_manager.dart';
import '../../core/sync/pocketbase_service.dart';
import '../../core/pip/pip_manager.dart';
import '../../core/audio/voice_alert_service.dart';
import '../../core/navigation/navigation_manager.dart';
import '../navigation/search_destination_sheet.dart';
import '../navigation/navigation_turn_banner.dart';
import '../navigation/cockpit_map_view.dart';
import '../widgets/lean_angle_gauge.dart';
import '../widgets/shift_light_bar.dart';

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

  // Navigation UI State
  bool _isInlineMapVisible = true;

  @override
  void initState() {
    super.initState();

    widget.obdService.telemetryStream.listen((frame) {
      if (mounted) setState(() => _currentFrame = frame);
    });

    widget.obdService.stateStream.listen((state) {
      if (mounted) setState(() {});
    });

    widget.sensorHub.dataStream.listen((sensorData) {
      if (mounted) setState(() => _currentSensor = sensorData);

      _checkAutoStartTrigger(sensorData.gpsSpeedKmh);

      if (NavigationManager().isNavigating) {
        NavigationManager().updateLocation(
          lat: sensorData.latitude,
          lng: sensorData.longitude,
          speedKmh: sensorData.gpsSpeedKmh,
        );
      }

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
    NavigationManager().addListener(_onNavStateChanged);
  }

  void _onTripStateChanged() {
    if (mounted) setState(() {});
  }

  void _onNavStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    TripManager().removeListener(_onTripStateChanged);
    NavigationManager().removeListener(_onNavStateChanged);
    super.dispose();
  }

  void _checkAutoStartTrigger(double speedKmh) {
    if (TripManager().isRecording) return;
    if (_isAutoStartDialogShowing) return;
    if (_autoStartCooldownUntil != null &&
        DateTime.now().isBefore(_autoStartCooldownUntil!)) {
      return;
    }

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
                setDialogState(() => _countdownSeconds--);
              } else {
                timer.cancel();
                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                _isAutoStartDialogShowing = false;
                _toggleTripRecording();
                VoiceAlertService().speakAlert("Trip otomatis dimulai!");
              }
            });

            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: const [
                  Icon(Icons.directions_bike,
                      color: Color(0xFF00FF66), size: 26),
                  SizedBox(width: 10),
                  Text(
                    'GERAKAN TERDETEKSI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
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
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          value: _countdownSeconds / 5.0,
                          strokeWidth: 4,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF00FF66)),
                          backgroundColor: Colors.white10,
                        ),
                      ),
                      Text(
                        '$_countdownSeconds',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
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
                      backgroundColor: Colors.redAccent.withOpacity(0.12),
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
                          fontSize: 11),
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
        backgroundColor: const Color(0xFF0F172A),
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
                color: Colors.white.withOpacity(0.04),
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
        backgroundColor: const Color(0xFF0F172A),
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
      backgroundColor: const Color(0xFF080B11),
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
    final navMgr = NavigationManager();
    final bool isRecording = tripMgr.isRecording;
    final bool isOverheat = isObdLive && _currentFrame.ectC > 100.0;
    final bool isLowBatt = isObdLive && _currentFrame.batteryVoltage < 11.8;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      child: Column(
        children: [
          _buildTopStatusBar(isOverheat, isLowBatt),
          const SizedBox(height: 6),

          // 16-Segment Shift Light Bar
          ShiftLightBar(
            rpm: isObdLive ? _currentFrame.rpm : (displaySpeed * 85.0).clamp(0.0, 9500.0),
            isLive: isObdLive,
          ),
          const SizedBox(height: 8),

          // Turn-by-Turn Navigation Instruction Banner
          NavigationTurnBanner(
            navMgr: navMgr,
            onToggleMap: () =>
                setState(() => _isInlineMapVisible = !_isInlineMapVisible),
            isMapVisible: _isInlineMapVisible,
          ),

          // If Navigating & Map Visible: Show Cockpit Live Route Map
          if (navMgr.isNavigating &&
              _isInlineMapVisible &&
              navMgr.currentRoute != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CockpitMapView(
                sensorData: _currentSensor,
                navMgr: navMgr,
                height: 180,
              ),
            ),

          // Main Center Cockpit: Giant Digital Speedometer + Sub-readout
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        displaySpeed.toStringAsFixed(0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 92,
                          fontWeight: FontWeight.w900,
                          height: 0.9,
                          fontFamily: 'monospace',
                          letterSpacing: -2.0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        speedUnit,
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Sub-Telemetry Pill (RPM, TPS, G-Force)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSubMetric(
                          'RPM',
                          isObdLive ? _currentFrame.rpm.toStringAsFixed(0) : '--',
                          const Color(0xFF00FF66),
                        ),
                        _buildSubDivider(),
                        _buildSubMetric(
                          'TPS',
                          isObdLive ? '${_currentFrame.tpsPercent.toStringAsFixed(0)}%' : '--',
                          const Color(0xFF00E5FF),
                        ),
                        _buildSubDivider(),
                        _buildSubMetric(
                          'G-FORCE',
                          '${_currentSensor.gForce >= 0 ? '+' : ''}${_currentSensor.gForce.toStringAsFixed(2)}G',
                          const Color(0xFFFFB300),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // MotoGP Lean Angle Horizontal Gauge
          LeanAngleGauge(
            currentAngle: _currentSensor.rollAngleDeg,
            maxLeft: tripMgr.maxLeanLeft,
            maxRight: tripMgr.maxLeanRight,
          ),
          const SizedBox(height: 10),

          // Unified Automotive Telemetry Ribbon (Seamless 4-Column Bar)
          _buildUnifiedTelemetryRibbon(isRecording, isObdLive, tripMgr, isOverheat, isLowBatt),
          const SizedBox(height: 10),

          // Racing Action Button
          _buildTripButton(isRecording, tripMgr),
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
    final navMgr = NavigationManager();
    final bool isRecording = tripMgr.isRecording;
    final bool isOverheat = isObdLive && _currentFrame.ectC > 100.0;
    final bool isLowBatt = isObdLive && _currentFrame.batteryVoltage < 11.8;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
      child: Row(
        children: [
          // Left Pane: Shift lights + Speedometer + Sub-readout + Button (44% width)
          Expanded(
            flex: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShiftLightBar(
                  rpm: isObdLive ? _currentFrame.rpm : (displaySpeed * 85.0).clamp(0.0, 9500.0),
                  isLive: isObdLive,
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          displaySpeed.toStringAsFixed(0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 78,
                            fontWeight: FontWeight.w900,
                            height: 0.9,
                            fontFamily: 'monospace',
                            letterSpacing: -2.0,
                          ),
                        ),
                        Text(
                          speedUnit,
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildSubMetric(
                                'RPM',
                                isObdLive ? _currentFrame.rpm.toStringAsFixed(0) : '--',
                                const Color(0xFF00FF66),
                              ),
                              _buildSubDivider(),
                              _buildSubMetric(
                                'TPS',
                                isObdLive ? '${_currentFrame.tpsPercent.toStringAsFixed(0)}%' : '--',
                                const Color(0xFF00E5FF),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _toggleTripRecording,
                    icon: Icon(isRecording ? Icons.stop_circle : Icons.navigation, size: 16),
                    label: Text(
                      isRecording
                          ? 'FINISH (${tripMgr.distanceKm.toStringAsFixed(1)} KM)'
                          : 'START TRIP',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Right Pane: Top Status Bar + (Map or Lean Gauge + Telemetry Ribbon) (56% width)
          Expanded(
            flex: 56,
            child: Column(
              children: [
                _buildTopStatusBar(isOverheat, isLowBatt),
                const SizedBox(height: 6),

                // Navigation Banner in Landscape
                NavigationTurnBanner(
                  navMgr: navMgr,
                  onToggleMap: () => setState(
                      () => _isInlineMapVisible = !_isInlineMapVisible),
                  isMapVisible: _isInlineMapVisible,
                ),

                Expanded(
                  child: navMgr.isNavigating &&
                          _isInlineMapVisible &&
                          navMgr.currentRoute != null
                      ? CockpitMapView(
                          sensorData: _currentSensor,
                          navMgr: navMgr,
                          height: double.infinity,
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            LeanAngleGauge(
                              currentAngle: _currentSensor.rollAngleDeg,
                              maxLeft: tripMgr.maxLeanLeft,
                              maxRight: tripMgr.maxLeanRight,
                            ),
                            _buildUnifiedTelemetryRibbon(isRecording, isObdLive, tripMgr, isOverheat, isLowBatt),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopStatusBar(bool isOverheat, bool isLowBatt) {
    final connColor = _getConnectionColor();
    return Row(
      children: [
        // Left PCX 160 Badge + Connection
        InkWell(
          onTap: _showBluetoothPicker,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                  ),
                  child: const Text(
                    'PCX 160',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: connColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _getConnectionStatusText(),
                  style: TextStyle(
                    color: connColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.white38, size: 14),
              ],
            ),
          ),
        ),

        const Spacer(),

        // Center Idiot Warning Lights (MIL, TEMP, BATT)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIdiotLight(Icons.warning_amber_rounded, false, Colors.orangeAccent),
            const SizedBox(width: 8),
            _buildIdiotLight(Icons.thermostat, isOverheat, Colors.redAccent),
            const SizedBox(width: 8),
            _buildIdiotLight(Icons.battery_alert, isLowBatt, Colors.redAccent),
          ],
        ),

        const Spacer(),

        // Right Action Controls
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Destination Search Button
            IconButton(
              icon: const Icon(Icons.search, color: Color(0xFF00FF66), size: 17),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Cari Tujuan Navigasi (OSRM)',
              onPressed: () {
                SearchDestinationSheet.show(
                  context,
                  LatLng(
                    _currentSensor.latitude != 0.0 ? _currentSensor.latitude : -6.2088,
                    _currentSensor.longitude != 0.0 ? _currentSensor.longitude : 106.8456,
                  ),
                );
              },
            ),

            // Cloud Sync Indicator
            ValueListenableBuilder<bool>(
              valueListenable: widget.pbService.isConnectedNotifier,
              builder: (context, isConnected, _) {
                return InkWell(
                  onTap: () => widget.pbService.autoLogin(),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? const Color(0xFF00FF66).withOpacity(0.12)
                          : Colors.white.withOpacity(0.04),
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
                          color: isConnected ? const Color(0xFF00FF66) : Colors.white24,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isConnected ? 'SYNC' : 'OFF',
                          style: TextStyle(
                            color: isConnected ? const Color(0xFF00FF66) : Colors.white38,
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
            const SizedBox(width: 2),

            // Native PiP Button
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt, color: Color(0xFF00E5FF), size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Floating PiP HUD',
              onPressed: _enterPipMode,
            ),
            const SizedBox(width: 2),

            // Simulation Toggle Pill
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.06),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: const Size(34, 22),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                widget.obdService.enableMockMode(!widget.obdService.isMockMode);
              },
              child: Text(
                widget.obdService.isMockMode ? 'Stop' : 'Sim',
                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdiotLight(IconData icon, bool isActive, Color alertColor) {
    return Icon(
      icon,
      size: 15,
      color: isActive ? alertColor : Colors.white.withOpacity(0.12),
    );
  }

  Widget _buildSubMetric(String label, String value, Color color) {
    return Row(
      children: [
        Text(
          '$label ',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.bold),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Widget _buildSubDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      height: 10,
      width: 1,
      color: Colors.white12,
    );
  }

  Widget _buildUnifiedTelemetryRibbon(bool isRecording, bool isObdLive, TripManager tripMgr, bool isOverheat, bool isLowBatt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1017),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildRibbonColumn(
            label: isRecording ? 'JARAK' : 'RANGE',
            value: isRecording ? '${tripMgr.distanceKm.toStringAsFixed(1)} KM' : (isObdLive ? '185 KM' : '--'),
            color: const Color(0xFF00FF66),
          ),
          _buildRibbonDivider(),
          _buildRibbonColumn(
            label: 'EFISIENSI',
            value: isObdLive
                ? (_currentFrame.speedKmh > 2 ? '${_currentFrame.instantaneousKml.toStringAsFixed(1)} km/L' : '${_currentFrame.fuelFlowLh.toStringAsFixed(2)} L/h')
                : (isRecording ? '45.5 km/L' : '--'),
            color: const Color(0xFFFFB300),
          ),
          _buildRibbonDivider(),
          _buildRibbonColumn(
            label: 'COOLANT',
            value: isObdLive ? '${_currentFrame.ectC.toStringAsFixed(0)}°C' : '--',
            color: isOverheat ? Colors.redAccent : const Color(0xFF00E5FF),
          ),
          _buildRibbonDivider(),
          _buildRibbonColumn(
            label: 'BATTERY',
            value: isObdLive ? '${_currentFrame.batteryVoltage.toStringAsFixed(1)}V' : (tripMgr.maxSpeedKmh > 0 ? '${tripMgr.maxSpeedKmh.toStringAsFixed(0)} km/h' : '--'),
            color: isLowBatt ? Colors.redAccent : const Color(0xFF7C4DFF),
          ),
        ],
      ),
    );
  }

  Widget _buildRibbonColumn({required String label, required String value, required Color color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildRibbonDivider() {
    return Container(
      height: 22,
      width: 1,
      color: Colors.white.withOpacity(0.06),
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
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 12),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
