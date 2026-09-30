import 'package:flutter/material.dart';

class PreRideScreen extends StatefulWidget {
  const PreRideScreen({super.key});

  @override
  State<PreRideScreen> createState() => _PreRideScreenState();
}

class _PreRideScreenState extends State<PreRideScreen> {
  double _standbyVolt = 12.5;
  double _crankingMinVolt = 10.4;
  bool _dtcClean = true;
  bool _tpsCalibrated = true;
  bool _ectNormal = true;
  bool _isTesting = false;

  void _runPreFlightScan() async {
    setState(() => _isTesting = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _isTesting = false;
        _standbyVolt = 12.6;
        _crankingMinVolt = 10.2;
        _dtcClean = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'PRE-RIDE INSPECTION',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Overall Status Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF00FF66).withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00FF66), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF00FF66), size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'ALL SYSTEMS GO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Sensor injeksi & kelistrikan aman untuk perjalanan jauh.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Diagnostic Checklist Items
            Expanded(
              child: ListView(
                children: [
                  _buildCheckItem(
                    title: 'Tegangan Standby Aki',
                    subtitle: 'Kontak ON tanpa beban',
                    value: '${_standbyVolt.toStringAsFixed(1)}V',
                    status: 'PRIMA (12.5V+)',
                    isOk: _standbyVolt >= 12.4,
                  ),
                  _buildCheckItem(
                    title: 'Cranking Voltage Dip Test',
                    subtitle: 'Drop tegangan saat tombol starter ditekan',
                    value: '${_crankingMinVolt.toStringAsFixed(1)}V',
                    status: 'SEHAT (>10.0V)',
                    isOk: _crankingMinVolt >= 10.0,
                  ),
                  _buildCheckItem(
                    title: 'DTC Injeksi / Sensor MIL',
                    subtitle: 'Scan kode kegagalan ECU Mode 03/07',
                    value: '0 DTC',
                    status: 'BERSIH',
                    isOk: _dtcClean,
                  ),
                  _buildCheckItem(
                    title: 'Kalibrasi Katup Gas (TPS)',
                    subtitle: 'Sensor posisi throttle tertutup rapat',
                    value: '0.0%',
                    status: 'NORMAL',
                    isOk: _tpsCalibrated,
                  ),
                  _buildCheckItem(
                    title: 'Plausibilitas Suhu Mesin (ECT)',
                    subtitle: 'Suhu coolant sesuai suhu udara sekitar',
                    value: '31°C',
                    status: 'MATCH AMBIENT',
                    isOk: _ectNormal,
                  ),
                ],
              ),
            ),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isTesting ? null : _runPreFlightScan,
                icon: _isTesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  _isTesting ? 'MEMERIKSA SENSOR...' : 'RE-SCAN PRE-RIDE CHECKLIST',
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckItem({
    required String title,
    required String subtitle,
    required String value,
    required String status,
    required bool isOk,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                status,
                style: TextStyle(
                  color: isOk ? const Color(0xFF00FF66) : Colors.redAccent,
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
}
