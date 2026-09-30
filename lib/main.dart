import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/bluetooth/obd_service.dart';
import 'core/sensors/sensor_hub.dart';
import 'core/sync/pocketbase_service.dart';
import 'ui/screens/home_screen.dart';

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

  // Start background sensor monitoring
  sensorHub.start();

  runApp(PcxTelemetryApp(
    obdService: obdService,
    sensorHub: sensorHub,
    pbService: pbService,
  ));
}

class PcxTelemetryApp extends StatelessWidget {
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
      home: HomeScreen(obdService: obdService),
    );
  }
}
