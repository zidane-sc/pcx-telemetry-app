import 'package:flutter/material.dart';
import '../../core/models/vehicle_profile.dart';
import '../../core/sensors/sensor_hub.dart';
import '../../core/vehicle/vehicle_manager.dart';

class VehiclePickerSheet extends StatefulWidget {
  final SensorHub sensorHub;

  const VehiclePickerSheet({super.key, required this.sensorHub});

  static Future<void> show(BuildContext context, SensorHub sensorHub) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
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
          backgroundColor: const Color(0xFF131B2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'TAMBAH KENDARAAN BARU',
            style: TextStyle(
              color: Colors.white,
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
                                ? const Color(0xFF00E5FF).withOpacity(0.2)
                                : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: type == VehicleType.motorcycle
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.two_wheeler, size: 16, color: Color(0xFF00E5FF)),
                              SizedBox(width: 6),
                              Text('MOTOR', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
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
                                ? const Color(0xFF00FF66).withOpacity(0.2)
                                : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: type == VehicleType.car
                                  ? const Color(0xFF00FF66)
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.directions_car, size: 16, color: Color(0xFF00FF66)),
                              SizedBox(width: 6),
                              Text('MOBIL', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
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
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _inputDecoration('Nama Kendaraan (Contoh: Vario 160 / Avanza)'),
                ),
                const SizedBox(height: 8),

                // Plate
                TextField(
                  controller: plateCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
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
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _inputDecoration('Kapasitas Mesin (cc)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: tankCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
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
              child: const Text('BATAL', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
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
              child: const Text('SIMPAN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
      filled: true,
      fillColor: Colors.white.withOpacity(0.04),
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
                const Text(
                  'PILIH KENDARAAN (GARASI)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
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
                      color: isActive ? const Color(0xFF131B2E) : const Color(0xFF0C1017),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isActive ? const Color(0xFF00E5FF) : Colors.white.withOpacity(0.06),
                        width: isActive ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(
                        isBike ? Icons.two_wheeler : Icons.directions_car,
                        color: isActive ? const Color(0xFF00E5FF) : Colors.white54,
                        size: 24,
                      ),
                      title: Text(
                        v.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: isActive ? FontWeight.w900 : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '${v.plateNumber.isNotEmpty ? '${v.plateNumber} • ' : ''}${v.engineCc.toStringAsFixed(0)}cc • Tangki ${v.tankCapacityL}L${!v.hasLeanSensor ? ' • Lean Mati (Mobil)' : ''}',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                      ),
                      trailing: isActive
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00FF66).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'AKTIF',
                                style: TextStyle(
                                  color: Color(0xFF00FF66),
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
                  side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _openAddVehicleDialog,
                icon: const Icon(Icons.add, color: Color(0xFF00E5FF), size: 16),
                label: const Text(
                  'TAMBAH KENDARAAN LAIN',
                  style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
