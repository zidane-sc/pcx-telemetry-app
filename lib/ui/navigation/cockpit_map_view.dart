import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/navigation/navigation_manager.dart';
import '../../core/sensors/sensor_hub.dart';
import '../common/cyber_map_tiles.dart';

class CockpitMapView extends StatefulWidget {
  final SensorHubData sensorData;
  final NavigationManager navMgr;
  final double height;

  const CockpitMapView({
    super.key,
    required this.sensorData,
    required this.navMgr,
    this.height = 200,
  });

  @override
  State<CockpitMapView> createState() => _CockpitMapViewState();
}

class _CockpitMapViewState extends State<CockpitMapView> {
  final MapController _mapController = MapController();
  bool _followMotorcycle = true;
  bool _courseUp = true; // Default to Course Up (Auto follows road/bike heading)

  @override
  void didUpdateWidget(covariant CockpitMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.sensorData.latitude != 0.0 &&
        widget.sensorData.longitude != 0.0) {
      final motorPos =
          LatLng(widget.sensorData.latitude, widget.sensorData.longitude);

      if (_followMotorcycle) {
        _mapController.move(motorPos, _mapController.camera.zoom);
      }

      // Rotate map smoothly in Course Up mode following vehicle heading
      if (_courseUp && widget.sensorData.headingDeg >= 0.0) {
        _mapController.rotate(-widget.sensorData.headingDeg);
      }
    }
  }

  void _toggleCourseUp() {
    setState(() {
      _courseUp = !_courseUp;
      if (!_courseUp) {
        _mapController.rotate(0.0); // Reset to North Up
      } else if (widget.sensorData.headingDeg >= 0.0) {
        _mapController.rotate(-widget.sensorData.headingDeg);
      }
    });
  }

  void _fitRouteBounds() {
    setState(() {
      _followMotorcycle = false;
      _courseUp = false;
      _mapController.rotate(0.0);
    });

    final route = widget.navMgr.currentRoute;
    if (route != null && route.polyline.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(route.polyline);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(24),
        ),
      );
    }
  }

  void _centerMotorcycle() {
    setState(() => _followMotorcycle = true);
    if (widget.sensorData.latitude != 0.0 &&
        widget.sensorData.longitude != 0.0) {
      _mapController.move(
        LatLng(widget.sensorData.latitude, widget.sensorData.longitude),
        16.5,
      );
      if (_courseUp && widget.sensorData.headingDeg >= 0.0) {
        _mapController.rotate(-widget.sensorData.headingDeg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.navMgr.currentRoute;
    final dest = widget.navMgr.destination;

    final LatLng motorPos = LatLng(
      widget.sensorData.latitude != 0.0 ? widget.sensorData.latitude : -6.2088,
      widget.sensorData.longitude != 0.0
          ? widget.sensorData.longitude
          : 106.8456,
    );

    // In North Up, rotate arrow by heading; in Course Up, arrow points straight forward
    final double markerRotationRad = _courseUp
        ? 0.0
        : (widget.sensorData.headingDeg * (pi / 180.0));

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E17),
          border: Border.all(
            color: const Color(0xFF00E5FF).withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: motorPos,
                initialZoom: 16.5,
                initialRotation: _courseUp && widget.sensorData.headingDeg >= 0.0
                    ? -widget.sensorData.headingDeg
                    : 0.0,
                onPositionChanged: (pos, hasGesture) {
                  if (hasGesture && _followMotorcycle) {
                    setState(() => _followMotorcycle = false);
                  }
                },
              ),
              children: [
                // 1. CARTO Dark Matter Retina Basemap with Disk Caching
                CyberMapTiles.buildTileLayer(),

                // 2. High-Visibility Double-Layer Neon Glow Route
                if (route != null)
                  PolylineLayer(
                    polylines: [
                      // Outer Cyan Glow
                      Polyline(
                        points: route.polyline,
                        strokeWidth: 8.0,
                        color: const Color(0xFF00E5FF).withOpacity(0.35),
                      ),
                      // Core Sharp Cyan Line
                      Polyline(
                        points: route.polyline,
                        strokeWidth: 4.0,
                        color: const Color(0xFF00E5FF),
                      ),
                    ],
                  ),

                // 3. Markers: Pulsing Motorcycle Radar & Destination Flag
                MarkerLayer(
                  markers: [
                    // Motorcycle Position Marker
                    Marker(
                      point: motorPos,
                      width: 36,
                      height: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00FF66).withOpacity(0.25),
                              border: Border.all(
                                color:
                                    const Color(0xFF00FF66).withOpacity(0.6),
                                width: 1.5,
                              ),
                            ),
                          ),
                          Transform.rotate(
                            angle: markerRotationRad,
                            child: const Icon(
                              Icons.navigation,
                              color: Color(0xFF00FF66),
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Destination Marker
                    if (dest != null)
                      Marker(
                        point: dest.toLatLng,
                        width: 36,
                        height: 36,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.redAccent,
                          size: 32,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 6),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Floating Controls Overlay (Top-Right)
            Positioned(
              top: 8,
              right: 8,
              child: Column(
                children: [
                  // Center / Follow Toggle Button
                  _buildControlPill(
                    icon: Icons.my_location,
                    color: _followMotorcycle
                        ? const Color(0xFF00FF66)
                        : Colors.white70,
                    isActive: _followMotorcycle,
                    tooltip: 'Ikuti Posisi Motor',
                    onTap: _centerMotorcycle,
                  ),
                  const SizedBox(height: 6),

                  // Course Up vs North Up Toggle
                  _buildControlPill(
                    icon: _courseUp ? Icons.navigation : Icons.explore,
                    color: _courseUp
                        ? const Color(0xFF00FF66)
                        : const Color(0xFF00E5FF),
                    isActive: _courseUp,
                    tooltip: _courseUp
                        ? 'Mode Course Up (Muter Mengikuti Arah Motor)'
                        : 'Mode North Up (Utara Selalu di Atas)',
                    onTap: _toggleCourseUp,
                  ),
                  const SizedBox(height: 6),

                  // Fit Entire Route Bounds Button
                  if (route != null)
                    _buildControlPill(
                      icon: Icons.zoom_out_map,
                      color: const Color(0xFF00E5FF),
                      isActive: false,
                      tooltip: 'Lihat Seluruh Rute',
                      onTap: _fitRouteBounds,
                    ),
                  const SizedBox(height: 6),

                  // Zoom In Button
                  _buildControlPill(
                    icon: Icons.add,
                    color: Colors.white70,
                    isActive: false,
                    tooltip: 'Perbesar',
                    onTap: () {
                      _mapController.move(
                        _mapController.camera.center,
                        _mapController.camera.zoom + 1,
                      );
                    },
                  ),
                  const SizedBox(height: 6),

                  // Zoom Out Button
                  _buildControlPill(
                    icon: Icons.remove,
                    color: Colors.white70,
                    isActive: false,
                    tooltip: 'Perkecil',
                    onTap: () {
                      _mapController.move(
                        _mapController.camera.center,
                        _mapController.camera.zoom - 1,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPill({
    required IconData icon,
    required Color color,
    required bool isActive,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E).withOpacity(0.9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? const Color(0xFF00FF66) : Colors.white12,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}
