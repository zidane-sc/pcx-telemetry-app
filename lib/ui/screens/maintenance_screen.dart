import 'package:flutter/material.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          _buildWearCard(
            component: 'Oli Mesin (SPX 2 / Fully Synthetic)',
            currentKm: 1850,
            limitKm: 2500,
            engineHours: 54,
            limitHours: 80,
            accentColor: const Color(0xFF00FF66),
          ),
          _buildWearCard(
            component: 'Roller & Slider CVT',
            currentKm: 6200,
            limitKm: 10000,
            engineHours: 190,
            limitHours: 300,
            accentColor: const Color(0xFF00E5FF),
          ),
          _buildWearCard(
            component: 'V-Belt Penggerak CVT',
            currentKm: 12400,
            limitKm: 15000,
            engineHours: 380,
            limitHours: 450,
            accentColor: const Color(0xFFFFB300),
          ),
          _buildWearCard(
            component: 'Busi Laser Iridium & Oli Gardan',
            currentKm: 5100,
            limitKm: 8000,
            engineHours: 150,
            limitHours: 240,
            accentColor: const Color(0xFF7C4DFF),
          ),
          _buildWearCard(
            component: 'Cairan Pendingin Radiator (Coolant)',
            currentKm: 8400,
            limitKm: 12000,
            engineHours: 250,
            limitHours: 360,
            accentColor: Colors.blueAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildWearCard({
    required String component,
    required int currentKm,
    required int limitKm,
    required int engineHours,
    required int limitHours,
    required Color accentColor,
  }) {
    final double progress = (currentKm / limitKm).clamp(0.0, 1.0);
    final int remainingKm = limitKm - currentKm;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  component,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Text(
                '$remainingKm KM LAGI',
                style: TextStyle(color: accentColor, fontWeight: FontWeight.w900, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Terpakai: $currentKm / $limitKm KM',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
              Text(
                'Jam Mesin: $engineHours / $limitHours Jam',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
