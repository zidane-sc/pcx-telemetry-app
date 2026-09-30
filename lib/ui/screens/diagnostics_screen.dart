import 'package:flutter/material.dart';
import '../../core/bluetooth/obd_service.dart';

class DiagnosticsScreen extends StatefulWidget {
  final ObdService obdService;

  const DiagnosticsScreen({super.key, required this.obdService});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  @override
  void initState() {
    super.initState();
    widget.obdService.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isConnected =
        widget.obdService.state == ObdConnectionState.connected ||
            widget.obdService.isMockMode;

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
          // Connection Warning Banner if Disconnected
          if (!isConnected)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.orangeAccent.withOpacity(0.4),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, color: Colors.orangeAccent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'MODUL DIAGNOSTIK TERKUNCI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Hubungkan dongle Kingbolen ELM327 ke soket DLC motor untuk mengaktifkan uji komponen fisik.',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          _buildTestCard(
            title: 'Radiator Fan Relay Routine',
            desc: 'Menyalakan kipas radiator selama 5 detik via Mode 08 untuk cek fungsionalitas relay.',
            icon: Icons.ac_unit,
            accentColor: const Color(0xFF00E5FF),
            isLocked: !isConnected,
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
            isLocked: !isConnected,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Triggering Fuel System Actuator Test...')),
              );
            },
          ),
          _buildTestCard(
            title: 'TPS Potentiometer Sweep Test',
            desc: 'Putar selongsong gas 0% ke 100% (mesin mati) untuk mendeteksi grafik resistor aus.',
            icon: Icons.show_chart,
            accentColor: const Color(0xFF00FF66),
            isLocked: !isConnected,
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
            isLocked: !isConnected,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Memulai Charging System Profiler...')),
              );
            },
          ),
          _buildTestCard(
            title: 'Clear Fault Codes & ECU Reset',
            desc: 'Menghapus riwayat kode kerusakan DTC Mode 04 dan mematikan lampu indikator MIL.',
            icon: Icons.delete_forever,
            accentColor: Colors.redAccent,
            isLocked: !isConnected,
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
    required bool isLocked,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocked ? Colors.white10 : accentColor.withOpacity(0.2),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isLocked
                      ? Colors.white.withOpacity(0.05)
                      : accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isLocked ? Icons.lock_outline : icon,
                  color: isLocked ? Colors.white38 : accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isLocked ? Colors.white60 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: TextStyle(
              color: isLocked ? Colors.white30 : Colors.white.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isLocked
                    ? Colors.white.withOpacity(0.04)
                    : accentColor.withOpacity(0.15),
                foregroundColor: isLocked ? Colors.white38 : accentColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isLocked ? Colors.white10 : accentColor,
                    width: 1,
                  ),
                ),
              ),
              onPressed: isLocked ? null : onTap,
              icon: Icon(isLocked ? Icons.lock : Icons.play_arrow, size: 14),
              label: Text(
                isLocked ? 'TERKUNCI' : 'MULAI TEST',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
