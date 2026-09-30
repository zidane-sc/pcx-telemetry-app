import 'package:flutter/material.dart';

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'RIWAYAT TRIP & BIAYA',
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
          _buildTripSummaryCard(
            date: 'Hari ini, 07:45 WIB',
            title: 'Rumah ➔ Kantor Dealls',
            distanceKm: 24.8,
            durationMin: 42,
            avgKml: 46.2,
            fuelCostIdr: 7350,
            maxLean: 'L 36° / R 39°',
          ),
          _buildTripSummaryCard(
            date: 'Kemarin, 18:20 WIB',
            title: 'Kantor Dealls ➔ Rumah',
            distanceKm: 25.1,
            durationMin: 55,
            avgKml: 41.5,
            fuelCostIdr: 8300,
            maxLean: 'L 32° / R 34°',
          ),
          _buildTripSummaryCard(
            date: '28 Sep 2026, 06:30 WIB',
            title: 'Sunday Morning Ride (Sentul)',
            distanceKm: 78.4,
            durationMin: 110,
            avgKml: 48.0,
            fuelCostIdr: 22350,
            maxLean: 'L 42° / R 43°',
          ),
        ],
      ),
    );
  }

  Widget _buildTripSummaryCard({
    required String date,
    required String title,
    required double distanceKm,
    required int durationMin,
    required double avgKml,
    required int fuelCostIdr,
    required String maxLean,
  }) {
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
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                'Rp ${fuelCostIdr.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
                style: const TextStyle(color: Color(0xFF00FF66), fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(date, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
          const Divider(color: Colors.white10, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTripStat('Jarak', '${distanceKm.toStringAsFixed(1)} KM'),
              _buildTripStat('Durasi', '$durationMin mnt'),
              _buildTripStat('Efisiensi', '${avgKml.toStringAsFixed(1)} km/L'),
              _buildTripStat('Rebah', maxLean),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTripStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }
}
