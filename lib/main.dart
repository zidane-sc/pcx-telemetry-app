import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:floating/floating.dart';
import 'core/bluetooth/obd_service.dart';
import 'core/sensors/sensor_hub.dart';
import 'core/sync/pocketbase_service.dart';
import 'core/audio/voice_alert_service.dart';
import 'core/rules/rule_service.dart';
import 'core/fuel/fuel_log_manager.dart';
import 'core/garage/expense_ledger.dart';
import 'core/telemetry/ride_report_service.dart';
import 'core/trip/trip_manager.dart';
import 'ui/sync/sync_setup_dialog.dart';
import 'ui/theme/theme_service.dart';
import 'core/logger/app_logger.dart';
import 'core/pip/pip_manager.dart';
import 'core/vehicle/vehicle_manager.dart';
import 'core/navigation/destination_store.dart';
import 'core/telemetry/performance_box.dart';
import 'ui/screens/home_screen.dart';
import 'ui/overlay/mini_pip_cockpit.dart';

/// Lets a background callback reach the navigator: the sync setup prompt is
/// raised from `main` after the first frame, outside any widget's context.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

    // Initialize Vehicle Manager & Performance Box
    await VehicleManager().initialize();
    await PerformanceBox().initialize();

    // Sprint 5: cost-of-ownership ledger and the fuel log it shares data with.
    await FuelLogManager().initialize();
    await ExpenseLedger().initialize();

    // Sprint 7: cockpit colour slot
    await ThemeService().initialize();

    // Pinned and recent destinations. Local only, so a failed read just means
    // the rider types the name once more -- never a blocked launch.
    await DestinationStore().initialize();

    // Configure lean sensor state based on active vehicle
    sensorHub.setLeanEnabled(VehicleManager().activeVehicle.hasLeanSensor);

    // Initialize Voice Alert Engine & Trip Manager
    await VoiceAlertService().init();
    await TripManager().init(pbService: pbService);

    // Sprint 4: emergency contact for the crash composer
    await RideReportService().init();

    // Background auto-login. Non-blocking: the phone-sensor side of the app is
    // fully usable with no cloud at all, so a dead tunnel must never hold up
    // the cockpit. Trips queue in local storage and flush when a host appears.
    pbService.autoLogin();

    // First run has no stored credentials -- they are no longer compiled in --
    // so prompt once, after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navCtx = navigatorKey.currentContext;
      if (navCtx == null) return;
      await ensureSyncSetup(navCtx, pbService);
    });

    // Enable native Picture-in-Picture when leaving to Google Maps
    PipManager().enableAutoPipOnLeave();

    // Start background sensor monitoring
    sensorHub.start();

    // Sprint 1: telemetry thresholds are evaluated by the Trigger→Action rule
    // engine (lib/core/rules/). The old `checkTelemetryThresholds` call here
    // was dead — it required isObdConnected, which was never passed, so the
    // early-return killed it. It also hard-coded dteKm: 185.0, an invented
    // number that could never reflect the real tank.
    await RuleService().init();

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
      title: 'PCX Cyber Telemetry',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080B11),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00FF66),
          surface: Color(0xFF0C1017),
        ),
      ),
      home: ThemeScope(
        service: ThemeService(),
        child: PiPSwitcher(
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
      ),
    );
  }
}
