import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

class CyberMapTiles {
  /// OpenStreetMap tile layer styled into high-contrast Cyberpunk Dark mode
  /// 100% free, zero API keys required, zero watermarks.
  static TileLayer buildTileLayer() {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.zidane.pcx_telemetry_app',
      maxZoom: 19,
      tileBuilder: (context, tileWidget, tile) {
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            -0.2126, -0.7152, -0.0722, 0, 255, // Red
            -0.2126, -0.7152, -0.0722, 0, 255, // Green
            -0.2126, -0.7152, -0.0722, 0, 255, // Blue
            0,       0,       0,       1, 0,   // Alpha
          ]),
          child: tileWidget,
        );
      },
    );
  }
}
