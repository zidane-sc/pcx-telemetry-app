import 'package:flutter/material.dart';
import '../../core/models/vehicle_profile.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/vehicle/vehicle_manager.dart';
import '../theme/theme_service.dart';

class VehiclePickerSheet extends StatefulWidget {
  final SensorHub sensorHub;

  const VehiclePickerSheet({super.key, required this.sensorHub});

  static Future<void> show(BuildContext context, SensorHub sensorHub) {
    return showModalBottomSheet(
      context: context,
      // Read from the caller's context, not from an instance: a static has no
      // `this`.
      backgroundColor: ThemeScope.slotOf(context).elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => VehiclePickerSheet(sensorHub: sensorHub),
    );
  }

  @override
  State<VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<VehiclePickerSheet> {

  /// The active cockpit colour slot. The sheet follows the cockpit rather than
  /// carrying its own palette: a rider who switches to Terik mode for a
  /// daylight fuel stop should not have to switch back to read the receipt.
  ThemeSlot get _slot => ThemeScope.slotOf(context);
  void _openAddVehicleDialog() {
    final nameCtrl = TextEditingController();
    final plateCtrl = TextEditingController();
    final ccCtrl = TextEditingController(text: '150');
    final tankCtrl = TextEditingController(text: '8.0');
    VehicleType type = VehicleType.motorcycle;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: _slot.elevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            'TAMBAH KENDARAAN BARU',
            style: TextStyle(
              color: _slot.text,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Vehicle Type Segmented
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setDlgState(() => type = VehicleType.motorcycle),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: type == VehicleType.motorcycle
                                ? _slot.accent.withOpacity(0.2)
                                : _slot.dim(0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: type == VehicleType.motorcycle
                                  ? _slot.accent
                                  : _slot.border(0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.two_wheeler, size: 16, color: _slot.accent),
                              SizedBox(width: 6),
                              Text('MOTOR', style: TextStyle(color: _slot.text, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => setDlgState(() => type = VehicleType.car),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: type == VehicleType.car
                                ? _slot.positive.withOpacity(0.2)
                                : _slot.dim(0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: type == VehicleType.car
                                  ? _slot.positive
                                  : _slot.border(0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.directions_car, size: 16, color: _slot.positive),
                              SizedBox(width: 6),
                              Text('MOBIL', style: TextStyle(color: _slot.text, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Name
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: _slot.text, fontSize: 13),
                  decoration: _inputDecoration('Nama Kendaraan (Contoh: Vario 160 / Avanza)'),
                ),
                const SizedBox(height: 8),

                // Plate
                TextField(
                  controller: plateCtrl,
                  style: TextStyle(color: _slot.text, fontSize: 13),
                  decoration: _inputDecoration('Plat Nomor (Contoh: B 5678 XYZ)'),
                ),
                const SizedBox(height: 8),

                // CC & Tank Capacity Row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ccCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: _slot.text, fontSize: 13),
                        decoration: _inputDecoration('Kapasitas Mesin (cc)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: tankCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: _slot.text, fontSize: 13),
                        decoration: _inputDecoration('Tangki BBM (Liter)'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('BATAL', style: TextStyle(color: _slot.dim(0.54))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _slot.accent),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;

                final newProfile = VehicleProfile(
                  id: 'veh_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  type: type,
                  plateNumber: plateCtrl.text.trim(),
                  engineCc: double.tryParse(ccCtrl.text.trim()) ?? 150.0,
                  tankCapacityL: double.tryParse(tankCtrl.text.trim()) ?? 8.0,
                  fuelType: 'Pertamax 92',
                  protocol: type == VehicleType.motorcycle
                      ? ObdProtocolType.kwp2000Fast
                      : ObdProtocolType.can11bit500k,
                  fuelMethod: type == VehicleType.motorcycle
                      ? FuelCalculationMethod.speedDensity
                      : FuelCalculationMethod.mafDirect,
                  hasLeanSensor: type == VehicleType.motorcycle,
                );

                await VehicleManager().saveVehicle(newProfile);
                await VehicleManager().selectVehicle(newProfile.id);
                widget.sensorHub.setLeanEnabled(newProfile.hasLeanSensor);

                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                }
              },
              child: Text('SIMPAN', style: TextStyle(color: _slot.onAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final vehMgr = VehicleManager();
    final vehicles = vehMgr.vehicles;
    final activeId = vehMgr.activeVehicle.id;

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
                  'PILIH KENDARAAN (GARASI)',
                  style: TextStyle(
                    color: _slot.text,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: _slot.dim(0.54), size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Vehicle Cards List
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: vehicles.length,
                itemBuilder: (context, index) {
                  final v = vehicles[index];
                  final bool isActive = v.id == activeId;
                  final isBike = v.type == VehicleType.motorcycle;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isActive ? _slot.elevated : _slot.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isActive ? _slot.accent : _slot.dim(0.06),
                        width: isActive ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(
                        isBike ? Icons.two_wheeler : Icons.directions_car,
                        color: isActive ? _slot.accent : _slot.dim(0.54),
                        size: 24,
                      ),
                      title: Text(
                        v.name,
                        style: TextStyle(
                          color: _slot.text,
                          fontWeight: isActive ? FontWeight.w900 : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '${v.plateNumber.isNotEmpty ? '${v.plateNumber} • ' : ''}${v.engineCc.toStringAsFixed(0)}cc • Tangki ${v.tankCapacityL}L${!v.hasLeanSensor ? ' • Lean Mati (Mobil)' : ''}',
                        style: TextStyle(color: _slot.dim(0.4), fontSize: 10),
                      ),
                      trailing: isActive
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _slot.positive.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'AKTIF',
                                style: TextStyle(
                                  color: _slot.positive,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                      onTap: () async {
                        await vehMgr.selectVehicle(v.id);
                        widget.sensorHub.setLeanEnabled(v.hasLeanSensor);
                        if (mounted) Navigator.pop(context);
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Add Vehicle Button
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _slot.accent.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _openAddVehicleDialog,
                icon: Icon(Icons.add, color: _slot.accent, size: 16),
                label: Text(
                  'TAMBAH KENDARAAN LAIN',
                  style: TextStyle(color: _slot.accent, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
