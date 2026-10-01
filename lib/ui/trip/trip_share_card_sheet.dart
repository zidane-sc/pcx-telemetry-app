import 'package:flutter/material.dart';
import '../../core/trip/trip_manager.dart';
import '../../core/trip/gpx_exporter.dart';

class TripShareCardSheet extends StatelessWidget {
  final TripRecord trip;

  const TripShareCardSheet({super.key, required this.trip});

  static Future<void> show(BuildContext context, TripRecord trip) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TripShareCardSheet(trip: trip),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${trip.startTime.day}/${trip.startTime.month}/${trip.startTime.year} • ${trip.startTime.hour.toString().padLeft(2, '0')}:${trip.startTime.minute.toString().padLeft(2, '0')} WIB';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'BAGIKAN HASIL TRIP',
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

            // 9:16 Instagram Story Card Container
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF080B11),
                    Color(0xFF131B2E),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.12),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Branding
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'PCX 160 eSP+',
                              style: TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'RIDE REPORT',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        dateStr,
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Giant Distance Readout
                  const Text(
                    'TOTAL JARAK TEMPUH',
                    style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        trip.distanceKm.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Color(0xFF00FF66),
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'KM',
                        style: TextStyle(
                          color: Color(0xFF00FF66),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${trip.durationMin.toStringAsFixed(0)} MENIT',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          Text(
                            'Rp ${trip.tripCostIdr.toStringAsFixed(0)} BBM',
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),

                  // 2x2 Telemetry Grid (Speed, Lean, Economy, Braking)
                  Row(
                    children: [
                      Expanded(
                        child: _buildShareStat(
                          label: 'TOP SPEED',
                          value: '${trip.maxSpeedKmh.toStringAsFixed(0)} km/h',
                          sub: 'Avg ${trip.avgSpeedKmh.toStringAsFixed(0)} km/h',
                          color: const Color(0xFF00E5FF),
                        ),
                      ),
                      Expanded(
                        child: _buildShareStat(
                          label: 'MOTOGP REBAH',
                          value: 'L${trip.maxLeanLeftDeg.toStringAsFixed(0)}° / R${trip.maxLeanRightDeg.toStringAsFixed(0)}°',
                          sub: 'Max Apex Lean',
                          color: const Color(0xFFFFB300),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildShareStat(
                          label: 'EFISIENSI BBM',
                          value: '${trip.avgKml.toStringAsFixed(1)} km/L',
                          sub: '${trip.fuelConsumedL.toStringAsFixed(2)} L terbakar',
                          color: const Color(0xFF7C4DFF),
                        ),
                      ),
                      Expanded(
                        child: _buildShareStat(
                          label: 'HARD BRAKING',
                          value: '${trip.hardBrakingCount}x Event',
                          sub: 'Rem mendadak',
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Bottom Watermark / Hash Tag
                  Center(
                    child: Text(
                      'CYBER TELEMETRY • TELEMETRY CLUSTER IOT',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.2),
                        fontSize: 9,
                        letterSpacing: 2.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Action Buttons: Export GPX (Strava) & Share
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      try {
                        final file = await GpxExporter.saveGpxToFile(trip);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF00FF66),
                              content: Text(
                                'File GPX berhasil disimpan di: ${file.path}\nSiap di-import ke Strava atau Google Earth!',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Gagal export GPX: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.file_download, size: 18),
                    label: const Text(
                      'EXPORT KE STRAVA (GPX)',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareStat({
    required String label,
    required String value,
    required String sub,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          sub,
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9),
        ),
      ],
    );
  }
}
