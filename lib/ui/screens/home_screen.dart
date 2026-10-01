import 'package:flutter/material.dart';
import '../../core/bluetooth/obd_service.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/sync/pocketbase_service.dart';
import 'cockpit_screen.dart';
import 'garage_screen.dart';
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
      GarageScreen(
        obdService: widget.obdService,
        pbService: widget.pbService,
      ),
      const TripsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080B11),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C1017),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (idx) => setState(() => _currentIndex = idx),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF00E5FF),
          unselectedItemColor: Colors.white30,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
          items: const [
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Icon(Icons.speed, size: 20),
              ),
              label: 'KOKPIT',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Icon(Icons.two_wheeler, size: 20),
              ),
              label: 'GARASI',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Icon(Icons.route, size: 20),
              ),
              label: 'JOURNAL',
            ),
          ],
        ),
      ),
    );
  }
}
