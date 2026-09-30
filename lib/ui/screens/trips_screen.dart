import 'dart:convert';
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

  void _showTimelineDetails(TripRecord item) {
    List<dynamic> points = [];
    try {
      points = jsonDecode(item.timelineData);
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TIMELINE & TELEMETRI RUTE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${points.length} Titik GPS Tersimpan (1 Hz / 1 detik)',
                        style: const TextStyle(color: Color(0xFF00FF66), fontSize: 11),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildDetailMiniCard('Top Speed', '${item.maxSpeedKmh.toStringAsFixed(0)} km/h'),
                  _buildDetailMiniCard('Avg Speed', '${item.avgSpeedKmh.toStringAsFixed(0)} km/h'),
                  _buildDetailMiniCard('Rem Keras', '${item.hardBrakingCount}x'),
                  _buildDetailMiniCard('Rebah L/R', '${item.maxLeanLeftDeg.toStringAsFixed(0)}° / ${item.maxLeanRightDeg.toStringAsFixed(0)}°'),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'LOG DETIK PER DETIK (GPS & REBAH):',
                style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: points.isEmpty
                    ? const Center(
                        child: Text(
                          'Timeline belum tersedia untuk trip ini.',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: points.length,
                        itemBuilder: (context, idx) {
                          final p = points[idx] as Map<String, dynamic>;
                          final sec = p['t'] ?? idx;
                          final spd = p['spd'] ?? 0;
                          final lean = p['lean'] ?? 0;
                          final lat = p['lat'] ?? 0.0;
                          final lng = p['lng'] ?? 0.0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Detik $sec s',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                                ),
                                Text(
                                  '$spd km/h',
                                  style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Rebah: ${lean.abs()}° ${lean < 0 ? 'L' : (lean > 0 ? 'R' : '')}',
                                  style: const TextStyle(color: Color(0xFFFFB300), fontSize: 11),
                                ),
                                Text(
                                  '($lat, $lng)',
                                  style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailMiniCard(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
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

                return InkWell(
                  onTap: () => _showTimelineDetails(item),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              dateStr,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Tap untuk timeline rute ➔',
                              style: TextStyle(
                                color: const Color(0xFF00E5FF).withOpacity(0.7),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildTripStat('Jarak', '${item.distanceKm.toStringAsFixed(1)} KM'),
                            _buildTripStat('Durasi', '${item.durationMin.toStringAsFixed(0)} mnt'),
                            _buildTripStat('Top Speed', '${item.maxSpeedKmh.toStringAsFixed(0)} km/h'),
                            _buildTripStat('Rem Keras', '${item.hardBrakingCount}x'),
                          ],
                        ),
                      ],
                    ),
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
