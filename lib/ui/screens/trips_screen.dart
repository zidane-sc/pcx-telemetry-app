import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../core/telemetry/ride_report_service.dart';
import '../../core/trip/trip_manager.dart';
import '../../core/trip/polyline_encoder.dart';
import '../common/cyber_map_tiles.dart';
import '../trip/trip_share_card_sheet.dart';

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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TripPlaybackSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = TripManager().history;

    return Scaffold(
      backgroundColor: const Color(0xFF080B11),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: const [
            Icon(Icons.route, color: Color(0xFF00E5FF), size: 22),
            SizedBox(width: 8),
            Text(
              'JOURNAL & RIWAYAT TRIP',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Color(0xFF00FF66), size: 20),
            tooltip: 'Sync ke PocketBase',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Menyinkronkan data trip ke Cloudflare PocketBase...'),
                  duration: Duration(seconds: 2),
                ),
              );
              await TripManager().flushUnsyncedTrips();
              if (mounted) {
                final anyUnsynced = TripManager().history.any((t) => !t.synced);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: anyUnsynced ? Colors.orangeAccent : const Color(0xFF00FF66),
                    content: Text(
                      anyUnsynced
                          ? 'Sebagian trip belum ter-upload (koneksi offline). Tersimpan aman di HP.'
                          : 'Semua trip berhasil disinkronkan ke server!',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
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
                  Icon(Icons.route, size: 48, color: Colors.white.withOpacity(0.15)),
                  const SizedBox(height: 12),
                  const Text(
                    'Belum ada trip yang direkam.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Buka tab KOKPIT & tap "START TRIP" sebelum jalan.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final item = history[index];
                final dateStr =
                    '${item.startTime.day}/${item.startTime.month} ${item.startTime.hour.toString().padLeft(2, '0')}:${item.startTime.minute.toString().padLeft(2, '0')} WIB';

                return InkWell(
                  onTap: () => _showTimelineDetails(item),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C1017),
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
                            Row(
                              children: [
                                Text(
                                  'Rp ${item.tripCostIdr.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Color(0xFF00FF66),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => TripShareCardSheet.show(context, item),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.share, size: 14, color: Color(0xFF00E5FF)),
                                  ),
                                ),
                              ],
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
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 11,
                              ),
                            ),
                            Row(
                              children: const [
                                Text(
                                  'Buka Playback Telemetri',
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 2),
                                Icon(Icons.arrow_forward_ios, color: Color(0xFF00E5FF), size: 10),
                              ],
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildTripStat('Jarak Tempuh', '${item.distanceKm.toStringAsFixed(1)} KM'),
                            _buildTripStat('Durasi', '${item.durationMin.toStringAsFixed(0)} mnt'),
                            _buildTripStat('Top Speed', '${item.maxSpeedKmh.toStringAsFixed(0)} km/h'),
                            _buildTripStat('Peak Rebah', 'L${item.maxLeanLeftDeg.toStringAsFixed(0)}° / R${item.maxLeanRightDeg.toStringAsFixed(0)}°'),
                          ],
                        ),

                        // Sprint 3: brake split. The whole point of classifying
                        // engine braking separately is that a rider can see it —
                        // "you used the engine 12 times, the brakes 3" is a
                        // technique conversation a combined count cannot start.
                        if (item.engineBrakingCount > 0 ||
                            item.serviceBrakingCount > 0) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildDecelBadge(
                                label: 'ENGINE BRAKE',
                                count: item.engineBrakingCount,
                                seconds: item.engineBrakeSeconds,
                                color: Colors.amber,
                                icon: Icons.trending_down,
                              ),
                              const SizedBox(width: 8),
                              _buildDecelBadge(
                                label: 'REM BRAKE',
                                count: item.serviceBrakingCount,
                                color: const Color(0xFFFF5252),
                                icon: Icons.speed,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  /// Sprint 3 badge for one deceleration class.
  Widget _buildDecelBadge({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    double? seconds,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.35), width: 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color.withOpacity(0.85),
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    seconds != null && seconds > 0
                        ? '$count× · ${seconds.toStringAsFixed(1)}s'
                        : '$count×',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class TripPlaybackSheet extends StatefulWidget {
  final TripRecord item;

  const TripPlaybackSheet({super.key, required this.item});

  @override
  State<TripPlaybackSheet> createState() => _TripPlaybackSheetState();
}

class _TripPlaybackSheetState extends State<TripPlaybackSheet> {
  final MapController _mapController = MapController();
  List<Map<String, dynamic>> _points = [];
  List<LatLng> _mapPoints = [];

  // Continuous 60 FPS sub-pixel scrubber progress (0.0 to points.length - 1)
  double _scrubProgress = 0.0;
  bool _isPlaying = false;
  bool _followBike = true;
  bool _courseUp = false; // Course-up vs North-up in playback
  int _speedMultiplier = 2; // 1x, 2x, 5x, 10x, 20x
  Timer? _playbackTimer;

  int _movingSeconds = 0;
  int _peakSpeedIndex = 0;
  int _peakLeanLeftIndex = 0;
  int _peakLeanRightIndex = 0;

  @override
  void initState() {
    super.initState();
    _parseTimeline();
  }

  void _parseTimeline() {
    try {
      final raw = jsonDecode(widget.item.timelineData) as List<dynamic>;
      _points = raw.map((e) => e as Map<String, dynamic>).toList();
      _mapPoints = _points.map((p) {
        final lat = (p['lat'] as num?)?.toDouble() ?? 0.0;
        final lng = (p['lng'] as num?)?.toDouble() ?? 0.0;
        return LatLng(lat, lng);
      }).where((l) => l.latitude != 0.0 && l.longitude != 0.0).toList();
    } catch (_) {
      _points = [];
      _mapPoints = [];
    }

    // Resilient fallback for legacy trips: decode polyline if timeline was empty
    if (_mapPoints.isEmpty && widget.item.routePolyline.isNotEmpty) {
      final pts = PolylineEncoder.decode(widget.item.routePolyline);
      for (int i = 0; i < pts.length; i++) {
        final p = pts[i];
        if (p[0] != 0.0 && p[1] != 0.0) {
          _mapPoints.add(LatLng(p[0], p[1]));
          _points.add({
            't': i,
            'lat': p[0],
            'lng': p[1],
            'spd': widget.item.avgSpeedKmh.round(),
            'lean': 0,
            'alt': 0,
          });
        }
      }
    }

    // Calculate moving time & peak events
    int maxSpd = 0;
    int maxLeft = 0;
    int maxRight = 0;

    for (int i = 0; i < _points.length; i++) {
      final p = _points[i];
      final spd = (p['spd'] as num?)?.toInt() ?? 0;
      final lean = (p['lean'] as num?)?.toInt() ?? 0;

      if (spd >= 2) {
        _movingSeconds += (i > 0) ? (((p['t'] ?? i) - (_points[i - 1]['t'] ?? (i - 1))) as int).clamp(1, 30) : 1;
      }

      if (spd > maxSpd) {
        maxSpd = spd;
        _peakSpeedIndex = i;
      }
      if (lean < -maxLeft) {
        maxLeft = -lean;
        _peakLeanLeftIndex = i;
      }
      if (lean > maxRight) {
        maxRight = lean;
        _peakLeanRightIndex = i;
      }
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitudeInRad;
    final lat2 = to.latitudeInRad;
    final dLng = to.longitudeInRad - from.longitudeInRad;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * (180.0 / pi) + 360.0) % 360.0;
  }

  void _cycleSpeed() {
    setState(() {
      if (_speedMultiplier == 1) {
        _speedMultiplier = 2;
      } else if (_speedMultiplier == 2) {
        _speedMultiplier = 5;
      } else if (_speedMultiplier == 5) {
        _speedMultiplier = 10;
      } else if (_speedMultiplier == 10) {
        _speedMultiplier = 20;
      } else {
        _speedMultiplier = 1;
      }
    });

    if (_isPlaying) {
      _startTimer();
    }
  }

  void _startTimer() {
    _playbackTimer?.cancel();

    // 30 FPS continuous sub-pixel interpolation loop (every 33ms)
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (_mapPoints.length < 2) {
        timer.cancel();
        return;
      }

      // Smooth progression rate: advances through keyframes proportionally
      final double step = 0.033 * _speedMultiplier * 2.5;

      if (_scrubProgress + step < _mapPoints.length - 1) {
        setState(() {
          _scrubProgress += step;
        });

        if (_followBike) {
          final pos = _getInterpolatedPosition();
          final bearing = _getInterpolatedBearing();
          _mapController.move(pos, _mapController.camera.zoom);
          if (_courseUp) {
            _mapController.rotate(-bearing);
          }
        }
      } else {
        setState(() {
          _scrubProgress = (_mapPoints.length - 1).toDouble();
          _isPlaying = false;
        });
        timer.cancel();
      }
    });
  }

  void _togglePlayback() {
    if (_mapPoints.isEmpty) return;

    if (_isPlaying) {
      _playbackTimer?.cancel();
      setState(() => _isPlaying = false);
    } else {
      if (_scrubProgress >= _mapPoints.length - 1.05) {
        _scrubProgress = 0.0;
      }
      setState(() => _isPlaying = true);
      _startTimer();
    }
  }

  void _onScrubChanged(double val) {
    if (_mapPoints.isEmpty) return;
    if (_isPlaying) {
      _playbackTimer?.cancel();
      setState(() => _isPlaying = false);
    }

    final double clampedVal = val.clamp(0.0, (_mapPoints.length - 1).toDouble());
    setState(() {
      _scrubProgress = clampedVal;
    });

    final pos = _getInterpolatedPosition();
    final bearing = _getInterpolatedBearing();
    _mapController.move(pos, _mapController.camera.zoom);
    if (_courseUp) {
      _mapController.rotate(-bearing);
    }
  }

  LatLng _getInterpolatedPosition() {
    if (_mapPoints.isEmpty) return const LatLng(-6.2088, 106.8456);
    if (_mapPoints.length == 1) return _mapPoints.first;

    final int baseIdx = _scrubProgress.floor().clamp(0, _mapPoints.length - 1);
    final int nextIdx = (baseIdx + 1).clamp(0, _mapPoints.length - 1);
    final double t = _scrubProgress - baseIdx;

    if (baseIdx == nextIdx) return _mapPoints[baseIdx];

    return LatLng(
      _mapPoints[baseIdx].latitude + (_mapPoints[nextIdx].latitude - _mapPoints[baseIdx].latitude) * t,
      _mapPoints[baseIdx].longitude + (_mapPoints[nextIdx].longitude - _mapPoints[baseIdx].longitude) * t,
    );
  }

  double _getInterpolatedBearing() {
    if (_mapPoints.length < 2) return 0.0;
    final int baseIdx = _scrubProgress.floor().clamp(0, _mapPoints.length - 1);
    final int nextIdx = (baseIdx + 1).clamp(0, _mapPoints.length - 1);

    if (baseIdx < nextIdx) {
      return _calculateBearing(_mapPoints[baseIdx], _mapPoints[nextIdx]);
    } else if (baseIdx > 0) {
      return _calculateBearing(_mapPoints[baseIdx - 1], _mapPoints[baseIdx]);
    }
    return 0.0;
  }

  List<Polyline> _buildSpeedColoredPolylines() {
    if (_mapPoints.length < 2) return [];

    final List<Polyline> lines = [];
    for (int i = 0; i < _mapPoints.length - 1; i++) {
      final spd = (_points.length > i) ? (_points[i]['spd'] ?? 0) : 0;

      Color segColor;
      if (spd < 30) {
        segColor = const Color(0xFF00FF66); // City Green (<30 km/h)
      } else if (spd < 60) {
        segColor = const Color(0xFF00E5FF); // Cruising Cyan (30-60 km/h)
      } else if (spd < 80) {
        segColor = const Color(0xFFFFB300); // Fast Amber (60-80 km/h)
      } else {
        segColor = const Color(0xFFFF3B30); // Top Speed Red (>80 km/h)
      }

      lines.add(
        Polyline(
          points: [_mapPoints[i], _mapPoints[i + 1]],
          strokeWidth: 4.5,
          color: segColor,
        ),
      );
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final LatLng centerPoint = _mapPoints.isNotEmpty
        ? _mapPoints[_mapPoints.length ~/ 2]
        : const LatLng(-6.2088, 106.8456);

    final int activeIdx = _scrubProgress.round().clamp(0, max(0, _points.length - 1));
    final currentSnapshot = (_points.isNotEmpty && activeIdx < _points.length)
        ? _points[activeIdx]
        : null;

    final currentSpd = currentSnapshot?['spd'] ?? 0;
    final currentLean = currentSnapshot?['lean'] ?? 0;
    final currentAlt = currentSnapshot?['alt'] ?? 0;
    final currentSec = currentSnapshot?['t'] ?? activeIdx;
    final totalSec = _points.isNotEmpty ? (_points.last['t'] ?? _points.length) : 0;

    final currentPos = _getInterpolatedPosition();
    final currentBearing = _getInterpolatedBearing();

    // Bearing rotation angle for motorcycle arrow
    // In North Up: arrow rotates by currentBearing to point down the road
    // In Course Up: map rotates by -currentBearing, arrow points straight up (0.0 rad)
    final double markerArrowRad = _courseUp ? 0.0 : (currentBearing * (pi / 180.0));

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Modal Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PETA RUTE & REKAMAN TELEMETRI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_mapPoints.length} Titik Rute (${_formatSeconds(_movingSeconds)} bergerak) • Heading: ${currentBearing.toStringAsFixed(0)}°',
                      style: const TextStyle(color: Color(0xFF00FF66), fontSize: 10),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Sprint 4: the PDF report goes to WhatsApp, Telegram,
                    // email — anywhere with a real share sheet. The IG story card
                    // below is for social; this is for archiving.
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Color(0xFF00E5FF), size: 18),
                      tooltip: 'Bagikan Laporan PDF',
                      onPressed: () async {
                        final ok = await RideReportService().shareReport(widget.item);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? 'Laporan PDF siap dibagikan'
                                : 'Gagal membuat laporan PDF'),
                            backgroundColor:
                                ok ? const Color(0xFF00FF66) : Colors.redAccent,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.share, color: Color(0xFF00E5FF), size: 18),
                      tooltip: 'Bagikan Story & Export GPX',
                      onPressed: () => TripShareCardSheet.show(context, widget.item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Interactive Heatmap Map with Rotating Directional Marker
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 230,
                width: double.infinity,
                child: _mapPoints.isEmpty
                    ? Container(
                        color: Colors.black26,
                        child: const Center(
                          child: Text(
                            'Koordinat GPS belum terekam pada trip ini.',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ),
                      )
                    : Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: centerPoint,
                              initialZoom: 15.0,
                              onPositionChanged: (pos, hasGesture) {
                                if (hasGesture && _followBike) {
                                  setState(() => _followBike = false);
                                }
                              },
                            ),
                            children: [
                              CyberMapTiles.buildTileLayer(),

                              // Speed-Colored Route Heatmap
                              PolylineLayer(
                                polylines: _buildSpeedColoredPolylines(),
                              ),

                              MarkerLayer(
                                markers: [
                                  // Start Point Marker
                                  Marker(
                                    point: _mapPoints.first,
                                    width: 22,
                                    height: 22,
                                    child: const Icon(
                                      Icons.play_circle_fill,
                                      color: Color(0xFF00FF66),
                                      size: 20,
                                    ),
                                  ),
                                  // Finish Point Marker
                                  Marker(
                                    point: _mapPoints.last,
                                    width: 22,
                                    height: 22,
                                    child: const Icon(
                                      Icons.flag_circle,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                  ),
                                  // Top Speed Location Marker
                                  if (_peakSpeedIndex > 0 && _peakSpeedIndex < _mapPoints.length)
                                    Marker(
                                      point: _mapPoints[_peakSpeedIndex],
                                      width: 24,
                                      height: 24,
                                      child: const Icon(
                                        Icons.bolt,
                                        color: Color(0xFF7C4DFF),
                                        size: 20,
                                      ),
                                    ),
                                  // 60 FPS Smooth Moving Directional Motorcycle Marker (Rotating to face the road!)
                                  Marker(
                                    point: currentPos,
                                    width: 36,
                                    height: 36,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFFFFB300).withOpacity(0.3),
                                            border: Border.all(color: const Color(0xFFFFB300), width: 2),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFFFFB300).withOpacity(0.4),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Transform.rotate(
                                          angle: markerArrowRad,
                                          child: const Icon(
                                            Icons.navigation,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // Map Controls: Follow & Course-Up Toggle
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Column(
                              children: [
                                // Follow Toggle
                                InkWell(
                                  onTap: () {
                                    setState(() => _followBike = true);
                                    _mapController.move(currentPos, _mapController.camera.zoom);
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF131B2E).withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _followBike ? const Color(0xFF00FF66) : Colors.white12,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.my_location,
                                      size: 15,
                                      color: _followBike ? const Color(0xFF00FF66) : Colors.white60,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),

                                // Course-Up / Road Heading Mode Toggle
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _courseUp = !_courseUp;
                                      if (!_courseUp) {
                                        _mapController.rotate(0.0);
                                      } else {
                                        _mapController.rotate(-currentBearing);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF131B2E).withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _courseUp ? const Color(0xFF00FF66) : const Color(0xFF00E5FF),
                                      ),
                                    ),
                                    child: Icon(
                                      _courseUp ? Icons.navigation : Icons.explore,
                                      size: 15,
                                      color: _courseUp ? const Color(0xFF00FF66) : const Color(0xFF00E5FF),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 8),

            // Speed Profile Sparkline Bar (Tap/Drag to scrub)
            if (_points.length > 2)
              GestureDetector(
                onHorizontalDragUpdate: (details) {
                  final renderBox = context.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    final width = renderBox.size.width - 32;
                    final localX = details.localPosition.dx.clamp(0.0, width);
                    final progress = localX / width;
                    _onScrubChanged(progress * (_mapPoints.length - 1));
                  }
                },
                child: Container(
                  height: 40,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C1017),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: CustomPaint(
                    painter: _SpeedSparklinePainter(
                      points: _points,
                      activeIndex: activeIdx,
                      maxSpeed: widget.item.maxSpeedKmh > 0 ? widget.item.maxSpeedKmh : 80.0,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // Playback Control Bar with 1x, 2x, 5x, 10x, 20x Speed Multiplier
            if (_mapPoints.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1017),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: const Color(0xFF00FF66),
                        size: 28,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _togglePlayback,
                    ),
                    const SizedBox(width: 8),
                    // High-Speed Multiplier Badge: 1x, 2x, 5x, 10x, 20x
                    InkWell(
                      onTap: _cycleSpeed,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                        ),
                        child: Text(
                          '${_speedMultiplier}x',
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF00E5FF),
                          inactiveTrackColor: Colors.white12,
                          thumbColor: const Color(0xFFFFB300),
                          overlayColor: const Color(0xFFFFB300).withOpacity(0.2),
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: _scrubProgress.clamp(0.0, (_mapPoints.length - 1).toDouble()),
                          min: 0,
                          max: (_mapPoints.length - 1).toDouble(),
                          onChanged: _onScrubChanged,
                        ),
                      ),
                    ),
                    Text(
                      '${_formatSeconds(currentSec)} / ${_formatSeconds(totalSec)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // Telemetry Inspector Cards for the Active Timestamp
            Row(
              children: [
                Expanded(
                  child: _buildInspectorCard('SPEED', '$currentSpd km/h', const Color(0xFF00E5FF)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildInspectorCard(
                    'REBAH',
                    '${currentLean.abs()}° ${currentLean < 0 ? 'L' : (currentLean > 0 ? 'R' : '')}',
                    const Color(0xFFFFB300),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildInspectorCard('ELEVASI', '$currentAlt m', const Color(0xFF00FF66)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildInspectorCard('TOP SPEED', '${widget.item.maxSpeedKmh.toStringAsFixed(0)} km/h', const Color(0xFF7C4DFF)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1017),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  String _formatSeconds(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _SpeedSparklinePainter extends CustomPainter {
  final List<Map<String, dynamic>> points;
  final int activeIndex;
  final double maxSpeed;

  _SpeedSparklinePainter({
    required this.points,
    required this.activeIndex,
    required this.maxSpeed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final double effectiveMax = max(maxSpeed, 20.0);
    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < points.length; i++) {
      final spd = ((points[i]['spd'] as num?)?.toDouble() ?? 0.0).clamp(0.0, effectiveMax);
      final x = (i / (points.length - 1)) * size.width;
      final y = size.height - (spd / effectiveMax) * (size.height - 4);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Area Fill Gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00E5FF).withOpacity(0.3),
          const Color(0xFF00E5FF).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Stroke Line
    final strokePaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, strokePaint);

    // Active Cursor Indicator
    if (activeIndex >= 0 && activeIndex < points.length) {
      final activeX = (activeIndex / (points.length - 1)) * size.width;
      final activeSpd = ((points[activeIndex]['spd'] as num?)?.toDouble() ?? 0.0).clamp(0.0, effectiveMax);
      final activeY = size.height - (activeSpd / effectiveMax) * (size.height - 4);

      final cursorPaint = Paint()
        ..color = const Color(0xFFFFB300)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(activeX, 0), Offset(activeX, size.height), cursorPaint);

      final dotPaint = Paint()..color = const Color(0xFFFFB300);
      canvas.drawCircle(Offset(activeX, activeY), 3.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedSparklinePainter oldDelegate) {
    return oldDelegate.activeIndex != activeIndex || oldDelegate.points != points;
  }
}
