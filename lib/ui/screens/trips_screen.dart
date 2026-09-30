import 'package:flutter/material.dart';
import '../../core/trip/trip_manager.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  @override
  void initState() {
    super.initState();
    TripManager().addListener(_onTripHistoryChanged);
    // Flush any pending unsynced trips when entering the screen
    TripManager().flushUnsyncedTrips();
  }

  void _onTripHistoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TripManager().removeListener(_onTripHistoryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = TripManager().history;

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
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Color(0xFF00E5FF), size: 20),
            tooltip: 'Sync ke PocketBase',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Menyinkronkan data trip ke Cloudflare PocketBase...')),
              );
              await TripManager().flushUnsyncedTrips();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFF00FF66),
                    content: Text('Sinkronisasi selesai!'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route, size: 48, color: Colors.white.withOpacity(0.2)),
                  const SizedBox(height: 12),
                  const Text(
                    'Belum ada trip yang direkam.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Buka tab Cockpit & tap "START TRIP" sebelum jalan.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final item = history[index];
                final dateStr =
                    '${item.startTime.day}/${item.startTime.month} ${item.startTime.hour.toString().padLeft(2, '0')}:${item.startTime.minute.toString().padLeft(2, '0')} WIB';

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131B2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Trip #${history.length - index}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: item.synced
                                      ? const Color(0xFF00FF66).withOpacity(0.15)
                                      : Colors.orangeAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.synced ? 'CLOUD SYNCED' : 'PENDING SYNC',
                                  style: TextStyle(
                                    color: item.synced
                                        ? const Color(0xFF00FF66)
                                        : Colors.orangeAccent,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Rp ${item.tripCostIdr.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Color(0xFF00FF66),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                      const Divider(color: Colors.white10, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildTripStat('Jarak', '${item.distanceKm.toStringAsFixed(1)} KM'),
                          _buildTripStat('Durasi', '${item.durationMin.toStringAsFixed(0)} mnt'),
                          _buildTripStat('Top Speed', '${item.maxSpeedKmh.toStringAsFixed(0)} km/h'),
                          _buildTripStat(
                            'Peak Rebah',
                            'L ${item.maxLeanLeftDeg.toStringAsFixed(0)}° / R ${item.maxLeanRightDeg.toStringAsFixed(0)}°',
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildTripStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
