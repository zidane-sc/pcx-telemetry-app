import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/bluetooth/obd_service.dart';
import 'core/sensors/sensor_hub.dart';
import 'core/sync/pocketbase_service.dart';
import 'core/audio/voice_alert_service.dart';
import 'core/overlay/overlay_manager.dart';
import 'ui/screens/home_screen.dart';
import 'ui/overlay/floating_bubble_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force dark OLED system bars
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0E17),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final obdService = ObdService();
  final sensorHub = SensorHub();
  final pbService = PocketBaseService();

  // Initialize Voice Alert Engine
  await VoiceAlertService().init();

  // Start background sensor monitoring
  sensorHub.start();

  // Wire telemetry frames to TTS Voice Alert Engine & Floating Overlay
  obdService.telemetryStream.listen((frame) {
    VoiceAlertService().checkTelemetryThresholds(
      ectC: frame.ectC,
      batteryVoltage: frame.batteryVoltage,
      dteKm: 185.0,
    );

    if (OverlayManager().isOverlayOpen) {
      OverlayManager().updateTelemetryData(
        dteKm: 185.0,
        kml: frame.instantaneousKml,
        ectC: frame.ectC,
      );
    }
  });

  runApp(PcxTelemetryApp(
    obdService: obdService,
    sensorHub: sensorHub,
    pbService: pbService,
  ));
}

/// Overlay Window Entry Point for Android SYSTEM_ALERT_WINDOW
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FloatingBubbleWidget(),
    ),
  );
}

class PcxTelemetryApp extends StatefulWidget {
  final ObdService obdService;
  final SensorHub sensorHub;
  final PocketBaseService pbService;

  const PcxTelemetryApp({
    super.key,
    required this.obdService,
    required this.sensorHub,
    required this.pbService,
  });

  @override
  State<PcxTelemetryApp> createState() => _PcxTelemetryAppState();
}

class _PcxTelemetryAppState extends State<PcxTelemetryApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user minimizes app or switches to Google Maps / Waze:
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (widget.obdService.state == ObdConnectionState.connected ||
          widget.obdService.isMockMode) {
        OverlayManager().showFloatingOverlay(
          dteKm: 185.0,
          kml: 46.5,
          ectC: 88.0,
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      // Returned to full cockpit
      OverlayManager().closeOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PCX Telemetry',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        primaryColor: const Color(0xFF00E5FF),
        textTheme: GoogleFonts.rajdhaniTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00FF66),
          surface: Color(0xFF131B2E),
        ),
      ),
      home: HomeScreen(obdService: widget.obdService),
    );
  }
}
