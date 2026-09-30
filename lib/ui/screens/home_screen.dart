import 'package:flutter/material.dart';
import '../../core/bluetooth/obd_service.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/sync/pocketbase_service.dart';
import 'cockpit_screen.dart';
import 'pre_ride_screen.dart';
import 'diagnostics_screen.dart';
import 'maintenance_screen.dart';
import 'trips_screen.dart';

class HomeScreen extends StatefulWidget {
  final ObdService obdService;
  final SensorHub sensorHub;
  final PocketBaseService pbService;

  const HomeScreen({
    super.key,
    required this.obdService,
    required this.sensorHub,
    required this.pbService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      CockpitScreen(
        obdService: widget.obdService,
        sensorHub: widget.sensorHub,
        pbService: widget.pbService,
      ),
      const PreRideScreen(),
      const DiagnosticsScreen(),
      const MaintenanceScreen(),
      const TripsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: const Color(0xFF0D1424),
        selectedItemColor: const Color(0xFF00E5FF),
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.speed),
            label: 'Cockpit',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checklist),
            label: 'Pre-Ride',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.build_circle),
            label: 'Diagnosa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.handyman),
            label: 'Servis',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.route),
            label: 'Trips',
          ),
        ],
      ),
    );
  }
}
