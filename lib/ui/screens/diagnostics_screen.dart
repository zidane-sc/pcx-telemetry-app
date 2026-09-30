import 'package:flutter/material.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'DIAGNOSTIK & UJI MOTOR',
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
          _buildTestCard(
            title: 'Radiator Fan Relay Routine',
            desc: 'Menyalakan kipas radiator selama 5 detik untuk cek fungsionalitas relay.',
            icon: Icons.ac_unit,
            accentColor: const Color(0xFF00E5FF),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Triggering Radiator Fan Relay Test (Mode 08)...')),
              );
            },
          ),
          _buildTestCard(
            title: 'Fuel Pump & Injector Click',
            desc: 'Memverifikasi dengungan pompa bensin dan denyut selenoid injektor.',
            icon: Icons.speed,
            accentColor: const Color(0xFFFFB300),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Triggering Fuel System Actuator Test...')),
              );
            },
          ),
          _buildTestCard(
            title: 'TPS Potentiometer Sweep Test',
            desc: 'Putar selongsong gas 0% ke 100% (mesin mati) untuk mendeteksi grafik putus/aus.',
            icon: Icons.show_chart,
            accentColor: const Color(0xFF00FF66),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Membuka TPS Sweep Graph Monitor...')),
              );
            },
          ),
          _buildTestCard(
            title: 'Charging System & Kiprok Stress Test',
            desc: 'Tahan putaran 3000 & 5000 RPM untuk cek overcharge (>15.2V) atau stator lemah.',
            icon: Icons.bolt,
            accentColor: const Color(0xFF7C4DFF),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Memulai Charging System Profiler...')),
              );
            },
          ),
          _buildTestCard(
            title: 'Clear Fault Codes & ECU Reset',
            desc: 'Menghapus riwayat kode kerusakan DTC Mode 04 dan mematikan lampu MIL.',
            icon: Icons.delete_forever,
            accentColor: Colors.redAccent,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mengirim Perintah ECU Reset (Mode 04)...')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTestCard({
    required String title,
    required String desc,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.2), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(desc, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor.withOpacity(0.15),
                foregroundColor: accentColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: accentColor, width: 1),
                ),
              ),
              onPressed: onTap,
              child: const Text('MULAI TEST', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
