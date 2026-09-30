import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:floating/floating.dart';
import 'core/bluetooth/obd_service.dart';
import 'core/sensors/sensor_hub.dart';
import 'core/sync/pocketbase_service.dart';
import 'core/audio/voice_alert_service.dart';
import 'core/trip/trip_manager.dart';
import 'core/logger/app_logger.dart';
import 'core/pip/pip_manager.dart';
import 'ui/screens/home_screen.dart';
import 'ui/overlay/mini_pip_cockpit.dart';

void main() async {
  runZonedGuarded(() async {
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

    // Initialize Global Crash Logger (Sentry Mini) immediately
    AppLogger().initialize(pb: pbService.pb);

    // Initialize Voice Alert Engine & Trip Manager
    await VoiceAlertService().init();
    await TripManager().init(pbService: pbService);

    // Background auto-login to PocketBase
    pbService.autoLogin();

    // Start background sensor monitoring
    sensorHub.start();

    // Wire telemetry frames to TTS Voice Alert Engine
    obdService.telemetryStream.listen((frame) {
      VoiceAlertService().checkTelemetryThresholds(
        ectC: frame.ectC,
        batteryVoltage: frame.batteryVoltage,
        dteKm: 185.0,
      );
    });

    runApp(PcxTelemetryApp(
      obdService: obdService,
      sensorHub: sensorHub,
      pbService: pbService,
    ));
  }, (error, stack) {
    AppLogger().logError(
      errorType: 'ZoneUncaughtException',
      stackTrace: '$error\n$stack',
    );
  });
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

class _PcxTelemetryAppState extends State<PcxTelemetryApp> {
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
      home: PiPSwitcher(
        childWhenDisabled: HomeScreen(
          obdService: widget.obdService,
          sensorHub: widget.sensorHub,
          pbService: widget.pbService,
        ),
        childWhenEnabled: MiniPipCockpit(
          obdService: widget.obdService,
          sensorHub: widget.sensorHub,
        ),
      ),
    );
  }
}
