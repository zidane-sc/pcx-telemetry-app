import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/trip/trip_manager.dart';
import '../../core/sync/pocketbase_service.dart';

class MaintenanceItem {
  final String key;
  final String name;
  final int limitKm;
  final int limitHours;
  final Color accentColor;

  const MaintenanceItem({
    required this.key,
    required this.name,
    required this.limitKm,
    required this.limitHours,
    required this.accentColor,
  });
}

class MaintenanceScreen extends StatefulWidget {
  final PocketBaseService? pbService;

  const MaintenanceScreen({super.key, this.pbService});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  double _baseOdometerKm = 0.0;
  final Map<String, double> _lastServiceKmMap = {};
  bool _isLoading = true;

  final List<MaintenanceItem> _items = const [
    MaintenanceItem(
      key: 'engine_oil',
      name: 'Oli Mesin (SPX 2 / Fully Synthetic)',
      limitKm: 2500,
      limitHours: 80,
      accentColor: Color(0xFF00FF66),
    ),
    MaintenanceItem(
      key: 'cvt_roller',
      name: 'Roller & Slider CVT',
      limitKm: 10000,
      limitHours: 300,
      accentColor: Color(0xFF00E5FF),
    ),
    MaintenanceItem(
      key: 'cvt_vbelt',
      name: 'V-Belt Penggerak CVT',
      limitKm: 15000,
      limitHours: 450,
      accentColor: Color(0xFFFFB300),
    ),
    MaintenanceItem(
      key: 'gear_oil',
      name: 'Busi Laser Iridium & Oli Gardan',
      limitKm: 8000,
      limitHours: 240,
      accentColor: Color(0xFF7C4DFF),
    ),
    MaintenanceItem(
      key: 'coolant',
      name: 'Cairan Pendingin Radiator (Coolant)',
      limitKm: 12000,
      limitHours: 360,
      accentColor: Colors.blueAccent,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadServiceHistory();
    TripManager().addListener(_onTripsChanged);
  }

  void _onTripsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TripManager().removeListener(_onTripsChanged);
    super.dispose();
  }

  Future<void> _loadServiceHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _baseOdometerKm = prefs.getDouble('bike_base_odometer_km') ?? 0.0;

      for (final item in _items) {
        _lastServiceKmMap[item.key] =
            prefs.getDouble('service_last_km_${item.key}') ?? 0.0;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  double get _totalRecordedTripKm {
    return TripManager().history.fold<double>(
          0.0,
          (sum, trip) => sum + trip.distanceKm,
        );
  }

  double get _currentMotorcycleOdometer =>
      _baseOdometerKm + _totalRecordedTripKm;

  void _editBaseOdometerDialog() {
    final ctrl = TextEditingController(
      text: _baseOdometerKm > 0 ? _baseOdometerKm.toStringAsFixed(0) : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'ODOMETER FISIK MOTOR',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan kilometer fisik PCX 160 saat ini agar hitungan countdown servis akurat:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputKeyBoardType.number,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Contoh: 12500',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                suffixText: 'KM',
                suffixStyle: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('BATAL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
            onPressed: () async {
              final val = double.tryParse(ctrl.text.trim()) ?? 0.0;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setDouble('bike_base_odometer_km', val);
              setState(() => _baseOdometerKm = val);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('SIMPAN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _recordServiceDialog(MaintenanceItem item) {
    final currentOdo = _currentMotorcycleOdometer;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: item.accentColor, size: 22),
            const SizedBox(width: 8),
            const Text(
              'CATAT SERVIS / GANTI PART',
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Sudah melakukan penggantian part pada odometer ${currentOdo.toStringAsFixed(0)} KM?\n\nHitungan mundur akan di-reset kembali ke ${item.limitKm} KM dan tersinkron ke cloud.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('BATAL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: item.accentColor,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setDouble('service_last_km_${item.key}', currentOdo);

              setState(() {
                _lastServiceKmMap[item.key] = currentOdo;
              });

              // Sync to PocketBase
              widget.pbService?.syncMaintenanceRecord(
                component: item.key,
                lastServiceKm: currentOdo,
                nextServiceKm: currentOdo + item.limitKm,
                status: 'ok',
              );

              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF00FF66),
                    content: Text(
                      'Servis ${item.name} berhasil dicatat pada odometer ${currentOdo.toStringAsFixed(0)} KM!',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }
            },
            child: const Text('KONFIRMASI SERVIS', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E17),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
      );
    }

    final totalOdo = _currentMotorcycleOdometer;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'SMART MAINTENANCE TRACKER',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Total Odometer Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF131B2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL ODOMETER MOTOR',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          totalOdo.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'KM',
                          style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Text(
                      'Terekam app: ${_totalRecordedTripKm.toStringAsFixed(1)} KM',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                    ),
                  ],
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.06),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: _editBaseOdometerDialog,
                  icon: const Icon(Icons.edit, size: 14, color: Color(0xFF00E5FF)),
                  label: const Text('Sesuaikan KM', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Dynamic Component Cards
          ..._items.map((item) {
            final lastKm = _lastServiceKmMap[item.key] ?? 0.0;
            final kmSinceService = (totalOdo - lastKm).clamp(0.0, 999999.0);
            final remainingKm = (item.limitKm - kmSinceService).round();
            final progress = (kmSinceService / item.limitKm).clamp(0.0, 1.0);

            return _buildRealWearCard(
              item: item,
              kmSinceService: kmSinceService,
              remainingKm: remainingKm,
              progress: progress,
              onTapService: () => _recordServiceDialog(item),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRealWearCard({
    required MaintenanceItem item,
    required double kmSinceService,
    required int remainingKm,
    required double progress,
    required VoidCallback onTapService,
  }) {
    final bool isOverdue = remainingKm <= 0;
    final bool isDueSoon = remainingKm > 0 && remainingKm <= 350;

    final Color badgeColor = isOverdue
        ? Colors.redAccent
        : (isDueSoon ? Colors.orangeAccent : item.accentColor);

    final String statusLabel = isOverdue
        ? 'TERLAMBAT ${remainingKm.abs()} KM'
        : '$remainingKm KM LAGI';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOverdue ? Colors.redAccent.withOpacity(0.6) : Colors.white.withOpacity(0.06),
          width: isOverdue ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(color: badgeColor, fontWeight: FontWeight.w900, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Terpakai: ${kmSinceService.toStringAsFixed(0)} / ${item.limitKm} KM',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
              InkWell(
                onTap: onTapService,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.build_circle_outlined, size: 14, color: item.accentColor),
                      const SizedBox(width: 4),
                      Text(
                        'Sudah Servis',
                        style: TextStyle(
                          color: item.accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
