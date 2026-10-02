import 'package:flutter/material.dart';
import '../../core/fuel/fuel_log_manager.dart';
import '../../core/sync/pocketbase_service.dart';
import '../theme/theme_service.dart';

class FuelLogSheet extends StatefulWidget {
  final double currentOdometer;
  final PocketBaseService pbService;

  const FuelLogSheet({
    super.key,
    required this.currentOdometer,
    required this.pbService,
  });

  static Future<void> show(
    BuildContext context, {
    required double currentOdometer,
    required PocketBaseService pbService,
  }) {
    return showModalBottomSheet(
      context: context,
      // Read from the caller's context, not from an instance: a static has no
      // `this`. The sheet body re-reads it for itself, so a theme change while
      // it is open still repaints it.
      backgroundColor: ThemeScope.slotOf(context).elevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FuelLogSheet(
        currentOdometer: currentOdometer,
        pbService: pbService,
      ),
    );
  }

  @override
  State<FuelLogSheet> createState() => _FuelLogSheetState();
}

class _FuelLogSheetState extends State<FuelLogSheet> {

  /// The active cockpit colour slot. The sheet follows the cockpit rather than
  /// carrying its own palette: a rider who switches to Terik mode for a
  /// daylight fuel stop should not have to switch back to read the receipt.
  ThemeSlot get _slot => ThemeScope.slotOf(context);
  final _odoCtrl = TextEditingController();
  final _litersCtrl = TextEditingController(text: '5.0');
  final _priceCtrl = TextEditingController(text: '12950');
  String _fuelType = 'Pertamax 92';
  bool _isFullTank = true;

  @override
  void initState() {
    super.initState();
    _odoCtrl.text = widget.currentOdometer.toStringAsFixed(0);
    FuelLogManager().addListener(_onDataChanged);
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FuelLogManager().removeListener(_onDataChanged);
    _odoCtrl.dispose();
    _litersCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _submitFillUp() async {
    final odo = double.tryParse(_odoCtrl.text.trim()) ?? widget.currentOdometer;
    final liters = double.tryParse(_litersCtrl.text.trim()) ?? 0.0;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 12950.0;

    if (liters <= 0) return;

    await FuelLogManager().addFillUp(
      odometerKm: odo,
      liters: liters,
      pricePerLiter: price,
      fuelType: _fuelType,
      isFullTank: _isFullTank,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _slot.positive,
          content: Text(
            'Pengisian ${(liters).toStringAsFixed(1)}L $_fuelType berhasil dicatat!',
            style: TextStyle(color: _slot.onAccent, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fuelMgr = FuelLogManager();
    final avgKml = fuelMgr.averageFullToFullKml;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: ListView(
          controller: scrollController,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_gas_station, color: _slot.positive, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'CATAT & KONSUMSI BBM',
                      style: TextStyle(
                        color: _slot.text,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close, color: _slot.dim(0.54), size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Top Summary Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _slot.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _slot.dim(0.08)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('TOTAL PENGELUARAN', 'Rp ${fuelMgr.totalSpentIdr.toStringAsFixed(0)}', _slot.positive),
                  Container(width: 1, height: 28, color: _slot.border(0.1)),
                  _buildStat('TOTAL BENSIN', '${fuelMgr.totalLiters.toStringAsFixed(1)} L', _slot.accent),
                  Container(width: 1, height: 28, color: _slot.border(0.1)),
                  _buildStat('FULL-TO-FULL', avgKml != null ? '${avgKml.toStringAsFixed(1)} km/L' : '--', _slot.warning),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Text(
              'FORM ISI BENSIN',
              style: TextStyle(color: _slot.dim(0.7), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
            ),
            const SizedBox(height: 8),

            // Input Fields
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _odoCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: _slot.text, fontSize: 13),
                    decoration: _inputDecoration('Odometer (KM)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _litersCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: _slot.text, fontSize: 13),
                    decoration: _inputDecoration('Jumlah Liter (L)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: _slot.text, fontSize: 13),
                    decoration: _inputDecoration('Harga / Liter (Rp)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _slot.dim(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _slot.border(0.12)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _fuelType,
                        dropdownColor: _slot.elevated,
                        style: TextStyle(color: _slot.text, fontSize: 12),
                        items: ['Pertalite 90', 'Pertamax 92', 'Pertamax Turbo 98', 'Shell V-Power', 'BP 92']
                            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _fuelType = val);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Isi Tangki Penuh (Full Tank)?', style: TextStyle(color: _slot.dim(0.7), fontSize: 12)),
                Switch(
                  value: _isFullTank,
                  activeColor: _slot.positive,
                  onChanged: (v) => setState(() => _isFullTank = v),
                ),
              ],
            ),

            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _slot.positive,
                  foregroundColor: _slot.onAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _submitFillUp,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('SIMPAN CATATAN BENSIN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ),

            const SizedBox(height: 18),
            Text(
              'RIWAYAT PENGISIAN BBM',
              style: TextStyle(color: _slot.dim(0.7), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
            ),
            const SizedBox(height: 8),

            if (fuelMgr.logs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Belum ada catatan isi bensin.',
                    style: TextStyle(color: _slot.dim(0.3), fontSize: 11),
                  ),
                ),
              )
            else
              ...fuelMgr.logs.map((e) {
                final d = '${e.timestamp.day}/${e.timestamp.month} ${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _slot.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _slot.dim(0.06)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e.liters.toStringAsFixed(1)}L • ${e.fuelType}',
                            style: TextStyle(color: _slot.text, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          Text(
                            '$d • Odo: ${e.odometerKm.toStringAsFixed(0)} KM',
                            style: TextStyle(color: _slot.dim(0.4), fontSize: 10),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Rp ${e.totalCostIdr.toStringAsFixed(0)}',
                            style: TextStyle(color: _slot.positive, fontWeight: FontWeight.w900, fontSize: 13, fontFamily: 'monospace'),
                          ),
                          if (e.calculatedKml != null)
                            Text(
                              '${e.calculatedKml!.toStringAsFixed(1)} km/L',
                              style: TextStyle(color: _slot.warning, fontWeight: FontWeight.bold, fontSize: 10),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: _slot.dim(0.4), fontSize: 8, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900, fontFamily: 'monospace')),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _slot.dim(0.3), fontSize: 11),
      filled: true,
      fillColor: _slot.dim(0.04),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}
