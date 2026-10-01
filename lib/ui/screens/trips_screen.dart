import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/trip/trip_manager.dart';
import '../common/cyber_map_tiles.dart';

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
      backgroundColor: const Color(0xFF131B2E),
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
                              'Interactive Playback ➔',
                              style: TextStyle(
                                color: const Color(0xFF00E5FF).withOpacity(0.7),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
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
  int _scrubberIndex = 0;
  bool _isPlaying = false;
  Timer? _playbackTimer;

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
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _togglePlayback() {
    if (_mapPoints.isEmpty) return;

    if (_isPlaying) {
      _playbackTimer?.cancel();
      setState(() => _isPlaying = false);
    } else {
      if (_scrubberIndex >= _mapPoints.length - 1) {
        _scrubberIndex = 0;
      }
      setState(() => _isPlaying = true);

      _playbackTimer?.cancel();
      // Tick every 250ms (4x speed simulation)
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
        if (_scrubberIndex < _mapPoints.length - 1) {
          setState(() {
            _scrubberIndex++;
          });
          _mapController.move(_mapPoints[_scrubberIndex], _mapController.camera.zoom);
        } else {
          timer.cancel();
          setState(() => _isPlaying = false);
        }
      });
    }
  }

  void _onScrubChanged(double val) {
    if (_mapPoints.isEmpty) return;
    final idx = val.round().clamp(0, _mapPoints.length - 1);
    setState(() {
      _scrubberIndex = idx;
    });
    _mapController.move(_mapPoints[idx], _mapController.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final LatLng centerPoint = _mapPoints.isNotEmpty
        ? _mapPoints[_mapPoints.length ~/ 2]
        : const LatLng(-6.2088, 106.8456);

    final currentSnapshot = (_points.isNotEmpty && _scrubberIndex < _points.length)
        ? _points[_scrubberIndex]
        : null;

    final currentSpd = currentSnapshot?['spd'] ?? 0;
    final currentLean = currentSnapshot?['lean'] ?? 0;
    final currentSec = currentSnapshot?['t'] ?? _scrubberIndex;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Modal Header
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
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_mapPoints.length} Titik GPS Tersimpan (1 Hz)',
                      style: const TextStyle(color: Color(0xFF00FF66), fontSize: 11),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Interactive Map with moving scrubber bike marker
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
                    : FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: centerPoint,
                          initialZoom: 15.0,
                        ),
                        children: [
                          CyberMapTiles.buildTileLayer(),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _mapPoints,
                                strokeWidth: 4.5,
                                color: const Color(0xFF00E5FF),
                              ),
                            ],
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
                              // Moving Scrubber Motorcycle Marker
                              if (_scrubberIndex < _mapPoints.length)
                                Marker(
                                  point: _mapPoints[_scrubberIndex],
                                  width: 32,
                                  height: 32,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFFFFB300).withOpacity(0.3),
                                          border: Border.all(color: const Color(0xFFFFB300), width: 2),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.navigation,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 10),

            // Playback Control Bar (Slider + Play/Pause)
            if (_mapPoints.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E17),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: const Color(0xFF00FF66),
                        size: 28,
                      ),
                      onPressed: _togglePlayback,
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
                          value: _scrubberIndex.toDouble(),
                          min: 0,
                          max: (_mapPoints.length - 1).toDouble(),
                          onChanged: _onScrubChanged,
                        ),
                      ),
                    ),
                    Text(
                      '${_formatSeconds(currentSec)} / ${_formatSeconds(_points.isNotEmpty ? _points.last['t'] ?? _points.length : 0)}',
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

            const SizedBox(height: 10),

            // Telemetry Inspector Cards for the Scrubber Moment
            Row(
              children: [
                Expanded(
                  child: _buildInspectorCard('SPEED', '$currentSpd km/h', const Color(0xFF00E5FF)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInspectorCard(
                    'REBAH',
                    '${currentLean.abs()}° ${currentLean < 0 ? 'L' : (currentLean > 0 ? 'R' : '')}',
                    const Color(0xFFFFB300),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInspectorCard('TOP SPEED', '${widget.item.maxSpeedKmh.toStringAsFixed(0)} km/h', const Color(0xFF7C4DFF)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInspectorCard('REM KERAS', '${widget.item.hardBrakingCount}x', Colors.redAccent),
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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E17),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
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
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
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
