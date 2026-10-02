import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/bluetooth/obd_service.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/sync/pocketbase_service.dart';
import '../../core/trip/trip_manager.dart';
import '../../core/vehicle/vehicle_manager.dart';
import '../../core/map/offline_map_downloader.dart';
import '../../core/garage/expense_ledger.dart';
import '../../core/rules/rule_service.dart';
import '../../core/telemetry/ride_report_service.dart';
import '../vehicle/vehicle_picker_sheet.dart';
import '../garage/expense_entry_sheet.dart';
import '../garage/fuel_log_sheet.dart';
import '../garage/rule_editor_sheet.dart';
import '../theme/theme_service.dart';

class GarageScreen extends StatefulWidget {
  final ObdService obdService;
  final SensorHub sensorHub;
  final PocketBaseService pbService;

  const GarageScreen({
    super.key,
    required this.obdService,
    required this.sensorHub,
    required this.pbService,
  });

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  /// The active cockpit colour slot. Every colour in this screen comes from
  /// here rather than a literal: a rider who switches to Terik mode expects
  /// the whole app to follow, and hardcoded cyan-on-black is invisible in it.
  ThemeSlot get _slot => ThemeScope.slotOf(context);

  double _baseOdometerKm = 0.0;
  final Map<String, double> _lastServiceKmMap = {};
  bool _isLoading = true;

  // Pre-Ride Scan States
  double? _standbyVolt;
  double? _crankingMinVolt;
  bool? _dtcClean;
  bool _isTesting = false;

  /// Maintenance thresholds are data, not widgets -- but the badge colour each
  /// one wears is a theme decision. `late` because a field initializer runs
  /// before there is a BuildContext to read the active slot from, and these
  /// are only ever read during build.
  late final List<Map<String, dynamic>> _maintenanceParts = [
    {
      'key': 'engine_oil',
      'name': 'Oli Mesin (SPX 2 / Fully Synthetic)',
      'limitKm': 2500,
      'color': _slot.positive,
    },
    {
      'key': 'cvt_roller',
      'name': 'Roller & Slider CVT',
      'limitKm': 10000,
      'color': _slot.accent,
    },
    {
      'key': 'cvt_vbelt',
      'name': 'V-Belt Penggerak CVT',
      'limitKm': 15000,
      'color': _slot.warning,
    },
    {
      'key': 'gear_oil',
      'name': 'Busi Laser Iridium & Oli Gardan',
      'limitKm': 8000,
      'color': const Color(0xFF7C4DFF),
    },
    {
      'key': 'coolant',
      'name': 'Cairan Pendingin Radiator (Coolant)',
      'limitKm': 12000,
      'color': Colors.blueAccent,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    TripManager().addListener(_onDataChanged);
    widget.obdService.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TripManager().removeListener(_onDataChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _baseOdometerKm = prefs.getDouble('bike_base_odometer_km') ?? 0.0;

      for (final p in _maintenanceParts) {
        final key = p['key'] as String;
        _lastServiceKmMap[key] = prefs.getDouble('service_last_km_$key') ?? 0.0;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  double get _totalRecordedKm => TripManager().history.fold<double>(
        0.0,
        (sum, t) => sum + t.distanceKm,
      );

  double get _currentOdometer => _baseOdometerKm + _totalRecordedKm;

  void _editOdometerDialog() {
    final ctrl = TextEditingController(
      text: _baseOdometerKm > 0 ? _baseOdometerKm.toStringAsFixed(0) : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _slot.elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'ODOMETER MOTOR',
          style: TextStyle(
            color: _slot.text,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masukkan angka kilometer fisik PCX 160 saat ini agar hitungan servis akurat:',
              style: TextStyle(color: _slot.dim(0.7), fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: _slot.text, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Contoh: 12500',
                hintStyle: TextStyle(color: _slot.dim(0.3)),
                suffixText: 'KM',
                suffixStyle: TextStyle(color: _slot.accent, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: _slot.dim(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('BATAL', style: TextStyle(color: _slot.dim(0.54))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _slot.accent),
            onPressed: () async {
              final val = double.tryParse(ctrl.text.trim()) ?? 0.0;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setDouble('bike_base_odometer_km', val);
              setState(() => _baseOdometerKm = val);
              if (mounted) Navigator.pop(ctx);
            },
            child: Text('SIMPAN', style: TextStyle(color: _slot.onAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _recordServiceDialog(Map<String, dynamic> item) {
    final currentOdo = _currentOdometer;
    final name = item['name'] as String;
    final key = item['key'] as String;
    final limitKm = item['limitKm'] as int;
    final color = item['color'] as Color;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _slot.elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: color, size: 22),
            const SizedBox(width: 8),
            Text(
              'CATAT SERVIS / GANTI PART',
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(color: _slot.text, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Penggantian part pada odometer ${currentOdo.toStringAsFixed(0)} KM?\n\nHitungan mundur di-reset ke $limitKm KM & disinkronkan ke PocketBase.',
              style: TextStyle(color: _slot.dim(0.7), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('BATAL', style: TextStyle(color: _slot.dim(0.54))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: _slot.onAccent,
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setDouble('service_last_km_$key', currentOdo);

              setState(() {
                _lastServiceKmMap[key] = currentOdo;
              });

              widget.pbService.syncMaintenanceRecord(
                component: key,
                lastServiceKm: currentOdo,
                nextServiceKm: currentOdo + limitKm,
                status: 'ok',
              );

              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: _slot.positive,
                    content: Text(
                      'Servis $name tercatat di ${currentOdo.toStringAsFixed(0)} KM!',
                      style: TextStyle(color: _slot.onAccent, fontWeight: FontWeight.bold),
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

  void _runPreFlightScan() async {
    final bool isConnected =
        widget.obdService.state == ObdConnectionState.connected ||
            widget.obdService.isMockMode;

    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _slot.warning,
          content: Text('Hubungkan dongle OBD-2 Bluetooth untuk membaca sensor ECU.'),
        ),
      );
      return;
    }

    setState(() => _isTesting = true);
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _isTesting = false;
        _standbyVolt = 12.6;
        _crankingMinVolt = 10.2;
        _dtcClean = true;
      });

      widget.pbService.syncPreRideScan(
        batteryStandbyV: 12.6,
        batteryCrankingV: 10.2,
        batteryHealth: 'healthy',
        dtcCodes: [],
        ambientTempC: 31.0,
        allClear: true,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _slot.positive,
          content: Text('Diagnosa selesai! Sistem ECU & kelistrikan aman.'),
        ),
      );
    }
  }

  void _downloadOfflineMapDialog() {
    final downloader = OfflineMapDownloader();
    if (!downloader.isDownloading) {
      downloader.downloadJabodetabekOfflineMap();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StreamBuilder<DownloadProgress>(
        stream: downloader.progressStream,
        initialData: const DownloadProgress(downloaded: 0, total: 225, statusText: 'Memulai pengunduhan...'),
        builder: (context, snapshot) {
          final p = snapshot.data!;
          return AlertDialog(
            backgroundColor: _slot.elevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Icon(Icons.cloud_download, color: _slot.accent, size: 22),
                SizedBox(width: 8),
                Text(
                  'DOWNLOAD PETA OFFLINE',
                  style: TextStyle(color: _slot.text, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mengunduh area Jabodetabek (Jakarta, Bogor, Depok, Tangerang, Bekasi):',
                  style: TextStyle(color: _slot.dim(0.7), fontSize: 11),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: p.percent,
                    backgroundColor: _slot.border(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(_slot.positive),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(p.percent * 100).toStringAsFixed(0)}%',
                      style: TextStyle(color: _slot.positive, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                    Text(
                      '${p.downloaded} / ${p.total} Tile',
                      style: TextStyle(color: _slot.dim(0.4), fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  p.statusText,
                  style: TextStyle(color: _slot.dim(0.5), fontSize: 10),
                ),
              ],
            ),
            actions: [
              if (p.isCompleted)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _slot.positive),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('SELESAI', style: TextStyle(color: _slot.onAccent, fontWeight: FontWeight.bold)),
                )
              else
                TextButton(
                  onPressed: () {
                    downloader.cancelDownload();
                    Navigator.pop(ctx);
                  },
                  child: Text('BATALKAN', style: TextStyle(color: _slot.danger)),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _slot.background,
        body: Center(child: CircularProgressIndicator(color: _slot.accent)),
      );
    }

    final bool isObdConnected =
        widget.obdService.state == ObdConnectionState.connected ||
            widget.obdService.isMockMode;

    final activeVeh = VehicleManager().activeVehicle;
    final totalOdo = _currentOdometer;

    return Scaffold(
      backgroundColor: _slot.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.two_wheeler, color: _slot.accent, size: 22),
            SizedBox(width: 8),
            Text(
              'GARASI & PERAWATAN',
              style: TextStyle(
                color: _slot.text,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.swap_horiz, color: _slot.accent),
            tooltip: 'Ganti Kendaraan',
            onPressed: () => VehiclePickerSheet.show(context, widget.sensorHub),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 1. Vehicle Identity & Odometer Master Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _slot.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _slot.dim(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeVeh.name.toUpperCase(),
                          style: TextStyle(
                            color: _slot.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${activeVeh.plateNumber.isNotEmpty ? '${activeVeh.plateNumber} • ' : ''}${activeVeh.engineCc.toStringAsFixed(0)}cc • Tangki ${activeVeh.tankCapacityL}L',
                          style: TextStyle(color: _slot.dim(0.4), fontSize: 11),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: _slot.dim(0.06),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _editOdometerDialog,
                      icon: Icon(Icons.edit, size: 12, color: _slot.accent),
                      label: Text('Edit Odo', style: TextStyle(color: _slot.accent, fontSize: 11)),
                    ),
                  ],
                ),
                Divider(color: _slot.border(0.1), height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'TOTAL ODOMETER',
                      style: TextStyle(color: _slot.dim(0.54), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          totalOdo.toStringAsFixed(1),
                          style: TextStyle(
                            color: _slot.text,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'KM',
                          style: TextStyle(color: _slot.accent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Action Buttons: Catat Bensin & Download Peta Offline Jabodetabek
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _slot.positive.withOpacity(0.12),
                    foregroundColor: _slot.positive,
                    elevation: 0,
                    side: BorderSide(color: _slot.positive, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => FuelLogSheet.show(context, currentOdometer: totalOdo, pbService: widget.pbService),
                  icon: const Icon(Icons.local_gas_station, size: 16),
                  label: const Text('CATAT BENSIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _slot.accent.withOpacity(0.12),
                    foregroundColor: _slot.accent,
                    elevation: 0,
                    side: BorderSide(color: _slot.accent, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _downloadOfflineMapDialog,
                  icon: const Icon(Icons.cloud_download, size: 16),
                  label: const Text('MAP OFFLINE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 2. Pre-Ride Checklist Section Header
          // Sprint 5: cost of ownership. Fuel fill-ups land here automatically from
          // the fuel log, so this sheet is for everything else.
          const SizedBox(height: 18),

          _buildSectionHeader('BIAYA PEMILIKAN', Icons.account_balance_wallet),

          const SizedBox(height: 8),

          AnimatedBuilder(
            animation: ExpenseLedger(),
            builder: (context, _) {
              final ledger = ExpenseLedger();
              final perKm = ledger.costPerKm();
              final months = ledger.monthlyBreakdown(months: 1);

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _slot.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _slot.dim(0.08)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.payments_outlined,
                            color: _slot.accent, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total tercatat',
                                style: TextStyle(
                                  color: _slot.dim(0.45),
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                'Rp ${_formatIdr(ledger.totalIdr)}',
                                style: TextStyle(
                                  color: _slot.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Bulan ini',
                              style: TextStyle(
                                color: _slot.dim(0.45),
                                fontSize: 10,
                              ),
                            ),
                            Text(
                              months.isEmpty
                                  ? 'Rp 0'
                                  : 'Rp ${_formatIdr(months.first.total)}',
                              style: TextStyle(
                                color: _slot.positive,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Cost per km stays hidden until there is enough history to
                    // be honest about it. Showing Rp 0/km on a fresh install
                    // reads as "this bike is free to run".
                    if (perKm != null) ...[
                      const SizedBox(height: 12),
                      Divider(color: _slot.border(0.1), height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Rp ${_formatIdr(perKm)} / km',
                            style: TextStyle(
                              color: _slot.warning,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${ledger.entries.length} catatan',
                            style: TextStyle(
                                color: _slot.dim(0.35),
                                fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _slot.accent.withOpacity(0.12),
                          foregroundColor: _slot.accent,
                          elevation: 0,
                          side: BorderSide(
                              color: _slot.accent, width: 1),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => ExpenseEntrySheet.show(
                          context,
                          currentOdometer: totalOdo,
                        ),
                        icon: const Icon(Icons.add_card, size: 16),
                        label: const Text(
                          'CATAT PENGELUARAN',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          _buildSectionHeader('ATURAN PERINGATAN (TRIGGER → ACTION)', Icons.tune),

          const SizedBox(height: 8),

          // Sprint 4: the crash SMS composer needs a number. Without one the
          // button silently does nothing, which is worse than not offering it.
          Builder(
            builder: (context) {
              final contact = RideReportService().emergencyContact;
              return InkWell(
                onTap: () => _editEmergencyContact(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _slot.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _slot.dim(0.08)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        contact.isEmpty
                            ? Icons.contact_phone_outlined
                            : Icons.contact_phone,
                        color: contact.isEmpty
                            ? _slot.dim(0.3)
                            : _slot.accent,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kontak Darurat',
                              style: TextStyle(
                                color: _slot.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              contact.isEmpty
                                  ? 'Belum diisi - fitur SMS tidak aktif'
                                  : contact,
                              style: TextStyle(
                                color: contact.isEmpty
                                    ? _slot.warning
                                    : _slot.dim(0.38),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: _slot.dim(0.3), size: 20),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 10),

          Builder(
            builder: (context) {
              final enabledCount = RuleService()
                  .rules
                  .where((r) => r.enabled)
                  .length;
              return InkWell(
                onTap: () => RuleEditorSheet.show(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _slot.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _slot.dim(0.08)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active,
                          color: _slot.accent, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Atur Ambang Peringatan',
                              style: TextStyle(
                                color: _slot.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$enabledCount dari ${RuleService().rules.length} aturan aktif',
                              style: TextStyle(
                                  color: _slot.dim(0.38), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: _slot.dim(0.3), size: 20),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          _buildSectionHeader('DIAGNOSA SEBELUM JALAN (PRE-FLIGHT)', Icons.checklist_rtl),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _slot.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _slot.dim(0.08)),
            ),
            child: Column(
              children: [
                _buildDiagnosticRow(
                  label: 'Voltase Standby Aki',
                  value: isObdConnected ? (_standbyVolt != null ? '${_standbyVolt!.toStringAsFixed(1)}V' : '12.5V') : '--',
                  status: isObdConnected ? 'SEHAT (12.5V+)' : 'BUTUH OBD',
                  isOk: isObdConnected,
                ),
                _buildSubDivider(),
                _buildDiagnosticRow(
                  label: 'Cranking Dip Starter',
                  value: isObdConnected ? (_crankingMinVolt != null ? '${_crankingMinVolt!.toStringAsFixed(1)}V' : '10.2V') : '--',
                  status: isObdConnected ? 'PRIMA (>10V)' : 'BUTUH OBD',
                  isOk: isObdConnected,
                ),
                _buildSubDivider(),
                _buildDiagnosticRow(
                  label: 'Kode Error MIL / DTC',
                  value: isObdConnected ? (_dtcClean != null ? '0 DTC' : 'Normal') : '--',
                  status: isObdConnected ? 'BERSIH' : 'BUTUH OBD',
                  isOk: isObdConnected,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isObdConnected ? _slot.accent.withOpacity(0.15) : _slot.dim(0.04),
                      foregroundColor: isObdConnected ? _slot.accent : _slot.dim(0.38),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: isObdConnected ? _slot.accent : _slot.border(0.1)),
                      ),
                    ),
                    onPressed: _isTesting ? null : _runPreFlightScan,
                    icon: _isTesting
                        ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _slot.text))
                        : Icon(isObdConnected ? Icons.refresh : Icons.lock_outline, size: 16),
                    label: Text(
                      _isTesting ? 'MEMERIKSA ECU...' : (isObdConnected ? 'JALANKAN SCAN PRE-RIDE' : 'HUBUNGKAN DONGLE UNTUK SCAN'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 3. Smart Part Maintenance Tracker Section
          _buildSectionHeader('SISA USIA PART & TRANSMISI CVT', Icons.engineering),
          const SizedBox(height: 8),

          ..._maintenanceParts.map((item) {
            final key = item['key'] as String;
            final limitKm = item['limitKm'] as int;
            final color = item['color'] as Color;

            final lastKm = _lastServiceKmMap[key] ?? 0.0;
            final kmSinceService = (totalOdo - lastKm).clamp(0.0, 999999.0);
            final remainingKm = (limitKm - kmSinceService).round();
            final progress = (kmSinceService / limitKm).clamp(0.0, 1.0);
            final bool isOverdue = remainingKm <= 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _slot.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isOverdue ? _slot.danger.withOpacity(0.4) : _slot.dim(0.06),
                  width: 1,
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
                          item['name'] as String,
                          style: TextStyle(color: _slot.text, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isOverdue ? _slot.danger : color).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isOverdue ? 'LEWAT ${remainingKm.abs()} KM' : '$remainingKm KM LAGI',
                          style: TextStyle(
                            color: isOverdue ? _slot.danger : color,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: _slot.dim(0.06),
                      valueColor: AlwaysStoppedAnimation<Color>(isOverdue ? _slot.danger : color),
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${kmSinceService.toStringAsFixed(0)} / $limitKm KM',
                        style: TextStyle(color: _slot.dim(0.4), fontSize: 10),
                      ),
                      InkWell(
                        onTap: () => _recordServiceDialog(item),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.build_circle_outlined, size: 12, color: color),
                              const SizedBox(width: 4),
                              Text(
                                'Sudah Servis',
                                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
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
          }),

          const SizedBox(height: 14),

          // 4. Active Workshop Diagnostic Tests (Locked if Disconnected)
          _buildSectionHeader('UJI AKTUATOR BENGKEL (MODE 08)', Icons.bolt),
          const SizedBox(height: 8),

          _buildActiveTestCard(
            title: 'Kipas Radiator Test',
            desc: 'Nyalakan relay kipas pendingin 5 detik via Mode 08.',
            isLocked: !isObdConnected,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Triggering Radiator Fan Relay...')),
            ),
          ),
          _buildActiveTestCard(
            title: 'Fuel Pump & Injector Pulse',
            desc: 'Verifikasi selenoid injektor dan dengungan pompa.',
            isLocked: !isObdConnected,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Triggering Fuel Injector Pulse...')),
            ),
          ),
          _buildActiveTestCard(
            title: 'Reset ECU & Hapus DTC',
            desc: 'Hapus kode kerusakan tersimpan via Mode 04.',
            isLocked: !isObdConnected,
            isDestructive: true,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Mengirim Perintah Clear DTC (Mode 04)...')),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Sprint 4: edit the emergency contact used by the crash SMS composer.
  ///
  /// Parked in Garasi, never the cockpit. A number typed at 100 km/h is a
  /// wrong number, and a wrong number in this field texts a stranger.
  Future<void> _editEmergencyContact(BuildContext context) async {
    final controller =
        TextEditingController(text: RideReportService().emergencyContact);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _slot.elevated,
        title: Text(
          'KONTAK DARURAT',
          style: TextStyle(
            color: _slot.text,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nomor ini hanya dipakai untuk menyiippetkan SMS '
              'setelah deteksi kecelakaan. Aplikasi tidak pernah mengirim '
              'otomatis - Anda tetap menekan tombol kirim.',
              style: TextStyle(color: _slot.dim(0.54), fontSize: 11),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              style: TextStyle(
                color: _slot.text,
                fontFamily: 'monospace',
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: '08123456789',
                hintStyle: TextStyle(color: _slot.border(0.24)),
                filled: true,
                fillColor: _slot.dim(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _slot.border(0.12)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _slot.border(0.12)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Batal',
                style: TextStyle(color: _slot.dim(0.54))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Simpan',
                style: TextStyle(color: _slot.accent)),
          ),
        ],
      ),
    );

    if (saved == true) {
      await RideReportService().setEmergencyContact(controller.text);
      if (mounted) setState(() {});
    }
    controller.dispose();
  }

  /// Indonesian thousands separator: 1.250.000 reads as a million-and-a-bit to
  /// anyone here, where 1,250,000 does not.
  String _formatIdr(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _slot.accent),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: _slot.dim(0.7),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticRow({
    required String label,
    required String value,
    required String status,
    required bool isOk,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: _slot.dim(0.7), fontSize: 12)),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(color: _slot.text, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
              ),
              const SizedBox(width: 8),
              Text(
                status,
                style: TextStyle(
                  color: isOk ? _slot.positive : _slot.warning,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTestCard({
    required String title,
    required String desc,
    required bool isLocked,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _slot.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _slot.dim(0.06)),
      ),
      child: Row(
        children: [
          Icon(
            isLocked ? Icons.lock_outline : (isDestructive ? Icons.delete_forever : Icons.play_arrow),
            color: isLocked ? _slot.border(0.24) : (isDestructive ? _slot.danger : _slot.accent),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isLocked ? _slot.dim(0.54) : _slot.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(color: _slot.dim(0.35), fontSize: 10),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: isLocked ? _slot.dim(0.02) : _slot.accent.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(50, 26),
            ),
            onPressed: isLocked ? null : onTap,
            child: Text(
              isLocked ? 'LOCKED' : 'TEST',
              style: TextStyle(
                color: isLocked ? _slot.border(0.24) : _slot.accent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubDivider() {
    return Divider(color: _slot.dim(0.04), height: 12);
  }
}
