import 'package:flutter_map/flutter_map.dart';

class CyberMapTiles {
  static const String cartoApiKey = 'cb1_45ge_1_42f188a5790255b2dc696b43';

  /// Official CARTO Dark Matter @2x Retina Tiles
  /// Ultra-sharp, authentic dark cyberpunk aesthetic, verified without watermarks.
  static TileLayer buildTileLayer() {
    return TileLayer(
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png?key=$cartoApiKey',
      subdomains: const ['a', 'b', 'c', 'd'],
      userAgentPackageName: 'com.zidane.pcx_telemetry_app',
      maxZoom: 20,
      retinaMode: true,
    );
  }
}
