import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/models/telemetry_data.dart';
import '../../core/models/vehicle_profile.dart';
import '../../core/bluetooth/obd_service.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/trip/trip_manager.dart';
import '../../core/sync/pocketbase_service.dart';
import '../../core/pip/pip_manager.dart';
import '../../core/audio/voice_alert_service.dart';
import '../../core/logger/app_logger.dart';
import '../../core/rules/rule_service.dart';
import '../../core/rules/trigger_rule.dart';
import '../../core/telemetry/crash_detector.dart';
import '../overlay/crash_alert_overlay.dart';
import '../../core/navigation/navigation_manager.dart';
import '../../core/vehicle/vehicle_manager.dart';
import '../../core/telemetry/performance_box.dart';
import '../../core/telemetry/dyno_power_calculator.dart';
import '../theme/theme_service.dart';
import '../navigation/nav_route_bar.dart';
import '../navigation/cockpit_map_view.dart';
import '../vehicle/vehicle_picker_sheet.dart';
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
  /// The active cockpit colour slot.
  ///
  /// A State has a `context`, so this can be a field-like getter and every one
  /// of the twenty-odd build helpers below can reach it. That matters: the
  /// telemetry ribbon drew its RPM/TPS/LOAD/TIMING labels in white at 40%,
  /// which is near-invisible on the light Terik background while the coloured
  /// numbers beside them stayed legible -- the labels explaining the numbers
  /// were the part that vanished.
  ThemeSlot get _slot => ThemeScope.slotOf(context);

  TelemetryFrame _currentFrame = TelemetryFrame.empty();
  SensorHubData _currentSensor = SensorHubData.empty();
  String? _connectedDeviceName;

  /// Sprint 4: crash detection. Armed when a trip starts, not on app launch,
  /// so a phone being picked up off a seat never registers as a fall.
  final CrashDetector _crashDetector = CrashDetector();
  bool _crashDialogOpen = false;

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

      // Update 0-60 km/h Drag Performance box
      final double currentSpeed = widget.obdService.state == ObdConnectionState.connected
          ? _currentFrame.speedKmh
          : sensorData.gpsSpeedKmh;
      PerformanceBox().onSpeedUpdate(currentSpeed);

      // Sprint 3: classify deceleration live, outside trip recording, so the
      // EB pill is meaningful whether or not a trip is running.
      TripManager().onLiveTelemetry(
        speedKmh: currentSpeed,
        obdFrame: widget.obdService.state == ObdConnectionState.connected
            ? _currentFrame
            : null,
      );

      // Sprint 4: crash detection. sensorData.gForce is the smoothed net
      // acceleration the pothole detector already computes, so no extra IMU
      // stream is needed.
      if (!_crashDialogOpen && !_isAutoStartDialogShowing) {
        final crash = _crashDetector.update(
          now: DateTime.now(),
          netG: sensorData.gForce,
          speedKmh: currentSpeed,
          isBike: VehicleManager().activeVehicle.hasLeanSensor,
        );
        if (crash.state == CrashState.countdown) {
          _crashDialogOpen = true;
          CrashAlertOverlay.show(
            context,
            detection: crash,
            onCancel: () {
              _crashDetector.cancel();
              _crashDialogOpen = false;
            },
            onExpired: () {
              // Logged, never dispatched. A crash event is worth keeping even
              // when the rider never saw the dialog.
              AppLogger().logError(
                errorType: 'CrashDetected',
                stackTrace: 'peakG=${crash.peakG}',
              );
            },
          ).then((_) {
            if (mounted) _crashDialogOpen = false;
          });
        }
      }

      // Check audio safety limits (lean limit, speed limit, overheat, low battery)
      // Sprint 1: telemetry thresholds now live in the Trigger→Action rule engine.
      // It applies hold-time hysteresis and cooldown, so a value hovering at the
      // threshold cannot machine-gun the speaker.
      RuleService().onTelemetry(
        RuleContext(
          frame: _currentFrame,
          sensor: sensorData,
          obdConnected: widget.obdService.state == ObdConnectionState.connected,
          isBike: VehicleManager().activeVehicle.hasLeanSensor,
          dteKm: null, // real DTE needs fill-to-full history — see Sprint 5
        ),
      );

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
    VehicleManager().addListener(_onVehicleChanged);
    PerformanceBox().addListener(_onPerfChanged);
  }

  void _onTripStateChanged() {
    // Sprint 4: arm crash detection when a trip starts, disarm when it stops.
    // Arming on app launch would mean a phone being picked up off the seat
    // could register as a fall.
    if (TripManager().isRecording) {
      _crashDetector.arm();
    } else if (_crashDetector.state == CrashState.countdown) {
      _crashDetector.cancel();
    }
    if (mounted) setState(() {});
  }

  void _onNavStateChanged() {
    if (mounted) setState(() {});
  }

  void _onVehicleChanged() {
    if (mounted) {
      widget.sensorHub.setLeanEnabled(VehicleManager().activeVehicle.hasLeanSensor);
      setState(() {});
    }
  }

  void _onPerfChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    TripManager().removeListener(_onTripStateChanged);
    NavigationManager().removeListener(_onNavStateChanged);
    VehicleManager().removeListener(_onVehicleChanged);
    PerformanceBox().removeListener(_onPerfChanged);
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
              backgroundColor: _slot.elevated,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.directions_bike,
                      color: _slot.positive, size: 26),
                  SizedBox(width: 10),
                  Text(
                    'GERAKAN TERDETEKSI',
                    style: TextStyle(
                      color: _slot.text,
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
                    style: TextStyle(color: _slot.dim(0.7), fontSize: 13),
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                              _slot.positive),
                          backgroundColor: _slot.border(0.1),
                        ),
                      ),
                      Text(
                        '$_countdownSeconds',
                        style: TextStyle(
                          color: _slot.text,
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
                      backgroundColor: _slot.danger.withOpacity(0.12),
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
                    child: Text(
                      'BATALKAN (BUKAN RIDING)',
                      style: TextStyle(
                          color: _slot.danger,
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
        SnackBar(
          backgroundColor: _slot.positive,
          content:
              Text('Trip Recording Dimulai! Pantau GPS, Speed & Telemetri.'),
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
        SnackBar(
          backgroundColor: _slot.warning,
          content:
              Text('Mode Picture-in-Picture (PiP) tidak didukung pada HP ini.'),
        ),
      );
      return;
    }

    final success = await pipMgr.enablePip();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _slot.danger,
          content: Text('Gagal mengaktifkan mode PiP.'),
        ),
      );
    }
  }

  void _showTripSummaryDialog(TripRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _slot.elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.flag, color: _slot.positive, size: 24),
            SizedBox(width: 8),
            Text(
              'RINGKASAN TRIP SELESAI',
              style: TextStyle(
                color: _slot.text,
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
                color: _slot.dim(0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_upload, color: _slot.accent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Trip otomatis tersimpan & di-sync ke Cloudflare PocketBase.',
                      style: TextStyle(color: _slot.dim(0.7), fontSize: 10),
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
                Text('TUTUP', style: TextStyle(color: _slot.accent)),
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
              style: TextStyle(color: _slot.dim(0.6), fontSize: 12)),
          Text(value,
              style: TextStyle(
                  color: _slot.text,
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
            backgroundColor: _slot.danger,
            content: const Text(
                'Izin Bluetooth ditolak. Buka Pengaturan HP untuk mengizinkan.'),
            action: SnackBarAction(
              label: 'PENGATURAN',
              textColor: _slot.text,
              onPressed: () => openAppSettings(),
            ),
          ),
        );
        return;
      }

      if (statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _slot.warning,
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
        backgroundColor: _slot.elevated,
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
                      Text(
                        'PILIH DONGLE BLUETOOTH',
                        style: TextStyle(
                          color: _slot.text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            color: _slot.dim(0.54), size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (devices.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'Belum ada perangkat paired.\nPairing dulu dongle Kingbolen (OBDII) di Bluetooth HP (PIN: 1234).',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _slot.dim(0.6), fontSize: 13),
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
                                  ? _slot.positive
                                  : _slot.accent,
                            ),
                            title: Text(
                              dev.name ?? 'Unknown Device',
                              style: TextStyle(
                                color: _slot.text,
                                fontWeight:
                                    isObd ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              dev.address,
                              style: TextStyle(
                                  color: _slot.dim(0.54), fontSize: 11),
                            ),
                            trailing: isObd
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _slot.positive
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'RECOMMENDED',
                                      style: TextStyle(
                                        color: _slot.positive,
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

    final activeVeh = VehicleManager().activeVehicle;
    final success = await widget.obdService.connect(device.address, protocol: activeVeh.protocol);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _slot.positive,
          content: Text('Terhubung ke ${device.name}! Protocol: ${activeVeh.protocol.label}'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _slot.danger,
          content: Text('Koneksi gagal. Pastikan kontak kendaraan posisi ON.'),
        ),
      );
    }
  }

  void _showQuickMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _slot.elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.picture_in_picture_alt, color: _slot.accent),
                title: Text('Mode Floating PiP', style: TextStyle(color: _slot.text, fontWeight: FontWeight.bold)),
                subtitle: Text('Buka mini cockpit melayang di atas Google Maps/Waze', style: TextStyle(color: _slot.dim(0.54), fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _enterPipMode();
                },
              ),
              ListTile(
                leading: Icon(
                  widget.obdService.isMockMode ? Icons.stop_circle : Icons.play_circle_outline,
                  color: widget.obdService.isMockMode ? _slot.danger : _slot.positive,
                ),
                title: Text(
                  widget.obdService.isMockMode ? 'Hentikan Simulator' : 'Mode Simulator (Demo)',
                  style: TextStyle(color: _slot.text, fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Simulasi data gas, rpm, dan bensin tanpa dongle', style: TextStyle(color: _slot.dim(0.54), fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.obdService.enableMockMode(!widget.obdService.isMockMode);
                },
              ),
              ListTile(
                leading: Icon(Icons.sync, color: _slot.positive),
                title: Text('Hubungkan Ulang Cloud PocketBase', style: TextStyle(color: _slot.text, fontWeight: FontWeight.bold)),
                subtitle: Text('Cek status koneksi Cloudflare Tunnel server', style: TextStyle(color: _slot.dim(0.54), fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.pbService.autoLogin();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mencoba menyambungkan ke server...')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ThemeScope subscription: changing the slot rebuilds this whole screen,
    // which is what a cockpit theme swap should do anyway.
    final themeSlot = ThemeScope.slotOf(context);
    return Scaffold(
      backgroundColor: themeSlot.background,
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;
            // Provide orientation to sensor hub so lean angle is mathematically correct
            widget.sensorHub.setOrientation(isLandscape: isLandscape);

            if (isLandscape) {
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
    final perfBox = PerformanceBox();
    final activeVeh = VehicleManager().activeVehicle;
    final bool isRecording = tripMgr.isRecording;
    // A channel is only comparable once the ECU has actually answered it.
    // `isObdLive` means the dongle is connected; on a motorcycle that is not
    // the same as "this ECU has a coolant sensor".
    final bool hasEct = _currentFrame.has(ObdChannel.ect);
    final bool hasBatt = _currentFrame.has(ObdChannel.batteryVoltage);
    final bool isOverheat = hasEct && _currentFrame.ectC > 100.0;
    final bool isLowBatt = hasBatt && _currentFrame.batteryVoltage < 11.8;

    final dyno = DynoPowerCalculator.estimatePowerAndTorque(
      speedKmh: displaySpeed,
      accelerationMps2: _currentSensor.accelerationMps2,
      rpm: _currentFrame.rpm,
      totalMassKg: activeVeh.type == VehicleType.motorcycle ? 202.0 : 1100.0,
    );

    final themeSlot = ThemeScope.slotOf(context);
    final Color mainTextColor = themeSlot.text;
    final Color pillBgColor = themeSlot.surface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      child: Column(
        children: [
          _buildCleanTopBar(activeVeh, isOverheat, isLowBatt),
          const SizedBox(height: 6),

          // 16-Segment Shift Light Bar
          ShiftLightBar(
            // No fabricated RPM from road speed. A shift light that guesses is worse
            // than a dark one.
            rpm: _currentFrame.rpm,
            isLive: _currentFrame.has(ObdChannel.rpm),
          ),
          const SizedBox(height: 6),

          // Route Bar: search entry point when idle, turn banner when
          // navigating. One slot, so the cockpit never has an empty gap where
          // the navigation controls would be.
          NavRouteBar(
            currentPosition: LatLng(
              _currentSensor.latitude != 0.0 ? _currentSensor.latitude : -6.2088,
              _currentSensor.longitude != 0.0 ? _currentSensor.longitude : 106.8456,
            ),
            isMapVisible: _isInlineMapVisible,
            onToggleMap: () =>
                setState(() => _isInlineMapVisible = !_isInlineMapVisible),
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

          // Center Cockpit: Giant Digital Speedometer + Sub-readout
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
                        style: TextStyle(
                          color: mainTextColor,
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
                        style: TextStyle(
                          color: _slot.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Rich Telemetry Pill (RPM, TPS, LOAD%, TIMING)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: pillBgColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _slot.border(0.1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSubMetric(
                          'RPM',
                          _currentFrame.has(ObdChannel.rpm)
                              ? _currentFrame.rpm.toStringAsFixed(0)
                              : '--',
                          _slot.positive,
                        ),
                        _buildSubDivider(),
                        _buildSubMetric(
                          'TPS',
                          _currentFrame.has(ObdChannel.tps)
                              ? '${_currentFrame.tpsPercent.toStringAsFixed(0)}%'
                              : '--',
                          _slot.accent,
                        ),
                        _buildSubDivider(),
                        _buildSubMetric(
                          'LOAD',
                          isObdLive ? '${_currentFrame.engineLoadPercent.toStringAsFixed(0)}%' : '--',
                          _slot.warning,
                        ),
                        _buildSubDivider(),
                        _buildSubMetric(
                          'TIMING',
                          isObdLive ? '${_currentFrame.timingAdvanceDeg.toStringAsFixed(0)}°' : '--',
                          _slot.timing,
                        ),
                      ],
                    ),
                  ),

                  // Live Dyno Power Output & Slope Pill
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildPillBadge(
                        '⚡ ${dyno['hp']!.toStringAsFixed(1)} HP • ${dyno['torqueNm']!.toStringAsFixed(1)} Nm',
                        _slot.positive,
                        pillBgColor,
                      ),
                      const SizedBox(width: 6),
                      _buildPillBadge(
                        '${_currentSensor.slopePercent >= 0 ? '▲ +' : '▼ '}${_currentSensor.slopePercent.toStringAsFixed(1)}% SLOPE',
                        _currentSensor.slopePercent.abs() > 6.0 ? _slot.warning : _slot.dim(0.7),
                        pillBgColor,
                      ),
                    ],
                  ),

                  // Pothole Shock Warning Banner
                  if (_currentSensor.potholeDetected) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: _slot.warning.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _slot.warning, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber, color: _slot.warning, size: 12),
                          SizedBox(width: 4),
                          Text('GUNCANGAN / LUBANG JALAN', style: TextStyle(color: _slot.warning, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],

                  // 0-60 km/h Performance Drag Timer Pill
                  const SizedBox(height: 6),
                  _buildDragTimerPill(perfBox),
                ],
              ),
            ),
          ),

          // Show Lean Gauge ONLY for motorcycles; for cars show Lateral G-Force Horizon
          if (activeVeh.hasLeanSensor)
            LeanAngleGauge(
              currentAngle: _currentSensor.rollAngleDeg,
              maxLeft: tripMgr.maxLeanLeft,
              maxRight: tripMgr.maxLeanRight,
              reading: _currentSensor.lean,
            ),
          const SizedBox(height: 8),

          // Unified Automotive Telemetry Ribbon (Seamless 4-Column Bar)
          _buildUnifiedTelemetryRibbon(isRecording, isObdLive, tripMgr, isOverheat, isLowBatt, activeVeh),
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
    final perfBox = PerformanceBox();
    final activeVeh = VehicleManager().activeVehicle;
    final bool isRecording = tripMgr.isRecording;
    // A channel is only comparable once the ECU has actually answered it.
    // `isObdLive` means the dongle is connected; on a motorcycle that is not
    // the same as "this ECU has a coolant sensor".
    final bool hasEct = _currentFrame.has(ObdChannel.ect);
    final bool hasBatt = _currentFrame.has(ObdChannel.batteryVoltage);
    final bool isOverheat = hasEct && _currentFrame.ectC > 100.0;
    final bool isLowBatt = hasBatt && _currentFrame.batteryVoltage < 11.8;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
      child: Row(
        children: [
          // Left Pane: Shift lights + Speedometer + Sub-readout + Drag Pill + Button (44% width)
          Expanded(
            flex: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShiftLightBar(
                  // No fabricated RPM from road speed. A shift light that guesses is worse
                  // than a dark one.
                  rpm: _currentFrame.rpm,
                  isLive: _currentFrame.has(ObdChannel.rpm),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          displaySpeed.toStringAsFixed(0),
                          style: TextStyle(
                            color: _slot.text,
                            fontSize: 78,
                            fontWeight: FontWeight.w900,
                            height: 0.9,
                            fontFamily: 'monospace',
                            letterSpacing: -2.0,
                          ),
                        ),
                        Text(
                          speedUnit,
                          style: TextStyle(
                            color: _slot.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _slot.elevated,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _slot.border(0.1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildSubMetric(
                                'RPM',
                                _currentFrame.has(ObdChannel.rpm)
                              ? _currentFrame.rpm.toStringAsFixed(0)
                              : '--',
                                _slot.positive,
                              ),
                              _buildSubDivider(),
                              _buildSubMetric(
                                'TPS',
                                _currentFrame.has(ObdChannel.tps)
                              ? '${_currentFrame.tpsPercent.toStringAsFixed(0)}%'
                              : '--',
                                _slot.accent,
                              ),
                              _buildSubDivider(),
                              _buildSubMetric(
                                'LOAD',
                                isObdLive ? '${_currentFrame.engineLoadPercent.toStringAsFixed(0)}%' : '--',
                                _slot.warning,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildDragTimerPill(perfBox),
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
                          ? _slot.danger.withOpacity(0.9)
                          : _slot.positive.withOpacity(0.9),
                      foregroundColor: _slot.onAccent,
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

          // Right Pane: Clean Top Bar + (Map or Lean Gauge + Telemetry Ribbon) (56% width)
          Expanded(
            flex: 56,
            child: Column(
              children: [
                _buildCleanTopBar(activeVeh, isOverheat, isLowBatt),
                const SizedBox(height: 6),

                // Route Bar in Landscape
                NavRouteBar(
                  currentPosition: LatLng(
                    _currentSensor.latitude != 0.0
                        ? _currentSensor.latitude
                        : -6.2088,
                    _currentSensor.longitude != 0.0
                        ? _currentSensor.longitude
                        : 106.8456,
                  ),
                  isMapVisible: _isInlineMapVisible,
                  compact: true,
                  onToggleMap: () =>
                      setState(() => _isInlineMapVisible = !_isInlineMapVisible),
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
                            if (activeVeh.hasLeanSensor)
                              LeanAngleGauge(
                                currentAngle: _currentSensor.rollAngleDeg,
                                maxLeft: tripMgr.maxLeanLeft,
                                maxRight: tripMgr.maxLeanRight,
                                reading: _currentSensor.lean,
                              ),
                            _buildUnifiedTelemetryRibbon(isRecording, isObdLive, tripMgr, isOverheat, isLowBatt, activeVeh),
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

  // ULTRA CLEAN TOP STATUS BAR (Un-cluttered, breathing room)
  Widget _buildCleanTopBar(
      VehicleProfile activeVeh, bool isOverheat, bool isLowBatt) {
    final themeSlot = ThemeScope.slotOf(context);
    final bool isBike = activeVeh.type == VehicleType.motorcycle;
    final bool isObdConnected = widget.obdService.state == ObdConnectionState.connected;

    return Row(
      children: [
        // Left: Sleek Vehicle Switcher Pill
        InkWell(
          onTap: () => VehiclePickerSheet.show(context, widget.sensorHub),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _slot.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _slot.dim(0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isBike ? Icons.two_wheeler : Icons.directions_car,
                  size: 14,
                  color: isBike ? _slot.accent : _slot.positive,
                ),
                const SizedBox(width: 6),
                Text(
                  activeVeh.name.split(' ').take(2).join(' '),
                  style: TextStyle(
                    color: _slot.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, color: _slot.dim(0.38), size: 14),
              ],
            ),
          ),
        ),

        const Spacer(),

        // Center: Discreet Warning Lights (Only appears if something is wrong!)
        if (isOverheat || isLowBatt || TripManager().isEngineBraking)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sprint 3: engine braking is a technique indicator, not a fault.
              // Amber, not red — a rider downshifting on a twisty road is doing
              // it right, and a red pill would train them to ignore it.
              if (TripManager().isEngineBraking)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _slot.warning.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _slot.warning, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.trending_down, color: _slot.warning, size: 12),
                      SizedBox(width: 4),
                      Text('EB', style: TextStyle(color: _slot.warning, fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              if ((isOverheat || isLowBatt) && TripManager().isEngineBraking)
                const SizedBox(width: 6),
              if (isOverheat)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _slot.danger.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.thermostat, color: _slot.danger, size: 12),
                      SizedBox(width: 4),
                      Text('OVERHEAT', style: TextStyle(color: _slot.danger, fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              if (isOverheat && isLowBatt) const SizedBox(width: 6),
              if (isLowBatt)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _slot.danger.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.battery_alert, color: _slot.danger, size: 12),
                      SizedBox(width: 4),
                      Text('LOW BATT', style: TextStyle(color: _slot.danger, fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),

        const Spacer(),

        // Right: Generously spaced action controls (Search POI, Bluetooth, Menu)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sprint 7: one button cycles the whole theme. A rider in a
            // helmet should not have to open a menu to make the dashboard
            // legible, so this is a cycle rather than a picker here.
            IconButton(
              icon: Icon(
                themeSlot.isLight ? Icons.wb_sunny : Icons.dark_mode_outlined,
                color: themeSlot.isLight
                    // A sun icon means "you are in the light slot", so it wears
                    // that slot's own warning tone. Hardcoding the amber here
                    // meant the icon drifted out of the palette the moment the
                    // token was retuned for contrast.
                    ? _slot.warning
                    : _slot.dim(0.38),
                size: 18,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Tema: ${themeSlot.label}',
              onPressed: () => ThemeScope.of(context).cycle(),
            ),

            // Search POI lives in the NavRouteBar, not here. As an 18dp glyph
            // sharing a row with theme and Bluetooth it read as a peer of
            // maintenance controls; it is the cockpit's most-used action.
            //
            // Bluetooth Connector Button
            IconButton(
              icon: Icon(
                Icons.bluetooth,
                color: isObdConnected ? _slot.positive : _slot.dim(0.38),
                size: 18,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              tooltip: 'Pilih Dongle Bluetooth',
              onPressed: _showBluetoothPicker,
            ),

            // More Options Menu
            IconButton(
              icon: Icon(Icons.more_vert, color: _slot.dim(0.54), size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              tooltip: 'Menu Tambahan',
              onPressed: _showQuickMenu,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPillBadge(String text, Color color, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDragTimerPill(PerformanceBox perfBox) {
    String dragText;
    Color dragColor;

    if (perfBox.state == DragState.measuring) {
      dragText = '0-60 KM/H: ${perfBox.current0to60Sec.toStringAsFixed(2)}s';
      dragColor = _slot.warning;
    } else if (perfBox.state == DragState.finished) {
      dragText = '0-60: ${perfBox.lastFinishedTimeSec.toStringAsFixed(2)}s (BEST: ${perfBox.best0to60Sec.toStringAsFixed(2)}s)';
      dragColor = _slot.positive;
    } else {
      dragText = perfBox.best0to60Sec > 0
          ? 'BEST 0-60: ${perfBox.best0to60Sec.toStringAsFixed(2)}s'
          : '0-60 DRAG READY';
      dragColor = _slot.dim(0.54);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: _slot.dim(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        dragText,
        style: TextStyle(
          color: dragColor,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSubMetric(String label, String value, Color color) {
    return Row(
      children: [
        Text(
          '$label ',
          style: TextStyle(color: _slot.dim(0.4), fontSize: 9, fontWeight: FontWeight.bold),
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
      color: _slot.border(0.12),
    );
  }

  Widget _buildUnifiedTelemetryRibbon(
    bool isRecording,
    bool isObdLive,
    TripManager tripMgr,
    bool isOverheat,
    bool isLowBatt,
    VehicleProfile activeVeh,
  ) {
    // The fuel model needs RPM, MAP and IAT together. If any is missing the
    // figure is not a degraded estimate, it is an unknown, and showing a
    // plausible km/L would be a fabrication.
    final bool hasFuelMath = _currentFrame.has(ObdChannel.rpm) &&
        _currentFrame.has(ObdChannel.map) &&
        _currentFrame.has(ObdChannel.iat);
    final bool hasEct = _currentFrame.has(ObdChannel.ect);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: _slot.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _slot.dim(0.08), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildRibbonColumn(
            label: isRecording ? 'JARAK' : 'RANGE',
            value: isRecording ? '${tripMgr.distanceKm.toStringAsFixed(1)} KM' : (isObdLive ? '${(activeVeh.tankCapacityL * 22).round()} KM' : '--'),
            color: _slot.positive,
          ),
          _buildRibbonDivider(),
          _buildRibbonColumn(
            label: 'EFISIENSI',
            value: hasFuelMath
                ? (_currentFrame.speedKmh > 2
                    ? '${_currentFrame.instantaneousKml.toStringAsFixed(1)} km/L'
                    : '${_currentFrame.fuelFlowLh.toStringAsFixed(2)} L/h')
                : '--',
            color: _slot.warning,
          ),
          _buildRibbonDivider(),
          _buildRibbonColumn(
            label: 'COOLANT',
            value: hasEct ? '${_currentFrame.ectC.toStringAsFixed(0)}°C' : '--',
            color: isOverheat ? _slot.danger : _slot.accent,
          ),
          _buildRibbonDivider(),
          _buildRibbonColumn(
            label: 'BATTERY',
            value: isObdLive ? '${_currentFrame.batteryVoltage.toStringAsFixed(1)}V' : (tripMgr.maxSpeedKmh > 0 ? '${tripMgr.maxSpeedKmh.toStringAsFixed(0)} km/h' : '--'),
            color: isLowBatt ? _slot.danger : _slot.timing,
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
            color: _slot.dim(0.4),
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
      color: _slot.dim(0.06),
    );
  }

  Widget _buildTripButton(bool isRecording, TripManager tripMgr) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: isRecording
              ? _slot.danger.withOpacity(0.9)
              : _slot.positive.withOpacity(0.9),
          foregroundColor: _slot.onAccent,
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
