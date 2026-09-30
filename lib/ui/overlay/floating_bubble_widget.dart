import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class FloatingBubbleWidget extends StatefulWidget {
  const FloatingBubbleWidget({super.key});

  @override
  State<FloatingBubbleWidget> createState() => _FloatingBubbleWidgetState();
}

class _FloatingBubbleWidgetState extends State<FloatingBubbleWidget> {
  double _dteKm = 185.0;
  double _kml = 46.5;
  double _ectC = 88.0;

  @override
  void initState() {
    super.initState();
    // Listen to data dispatched from main app
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data != null) {
        try {
          final map = jsonDecode(data.toString());
          if (mounted) {
            setState(() {
              _dteKm = (map['dteKm'] ?? 185.0).toDouble();
              _kml = (map['kml'] ?? 46.5).toDouble();
              _ectC = (map['ectC'] ?? 88.0).toDouble();
            });
          }
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isOverheat = _ectC > 100.0;

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E17).withOpacity(0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isOverheat ? Colors.redAccent : const Color(0xFF00E5FF).withOpacity(0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // PCX Pill Icon
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFF00E5FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.two_wheeler, color: Colors.black, size: 16),
              ),
              const SizedBox(width: 10),

              // Range Metric
              _buildMiniMetric('RANGE', '${_dteKm.toStringAsFixed(0)} KM', const Color(0xFF00FF66)),
              _buildDivider(),

              // Economy Metric
              _buildMiniMetric('BBM', '${_kml.toStringAsFixed(1)} km/L', const Color(0xFFFFB300)),
              _buildDivider(),

              // ECT Metric
              _buildMiniMetric(
                'ECT',
                '${_ectC.toStringAsFixed(0)}°C',
                isOverheat ? Colors.redAccent : const Color(0xFF00E5FF),
              ),

              const SizedBox(width: 8),
              // Close / Back button
              InkWell(
                onTap: () {
                  FlutterOverlayWindow.closeOverlay();
                },
                child: const Icon(Icons.close, color: Colors.white54, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniMetric(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      height: 18,
      width: 1,
      color: Colors.white12,
    );
  }
}
