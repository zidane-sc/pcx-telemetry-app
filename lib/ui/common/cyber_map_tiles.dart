import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

class CyberMapTiles {
  static const String cartoApiKey = 'cb1_45ge_1_42f188a5790255b2dc696b43';

  /// Official CARTO Dark Matter @2x Retina Tiles with Offline Disk Caching
  static TileLayer buildTileLayer() {
    return TileLayer(
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png?key=$cartoApiKey',
      subdomains: const ['a', 'b', 'c', 'd'],
      userAgentPackageName: 'com.zidane.pcx_telemetry_app',
      maxZoom: 20,
      retinaMode: true,
      tileProvider: CachedCartoTileProvider(),
    );
  }
}

class CachedCartoTileProvider extends TileProvider {
  CachedCartoTileProvider({super.headers});

  @override
  ImageProvider<Object> getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) {
    final url = getTileUrl(coordinates, options);
    final cacheKey = '${coordinates.z}_${coordinates.x}_${coordinates.y}.png';
    return CachedDiskImageProvider(url: url, cacheKey: cacheKey);
  }
}

class CachedDiskImageProvider extends ImageProvider<CachedDiskImageProvider> {
  final String url;
  final String cacheKey;

  const CachedDiskImageProvider({required this.url, required this.cacheKey});

  @override
  Future<CachedDiskImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedDiskImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedDiskImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 2.0, // Retina @2x scale
      informationCollector: () => [DiagnosticsProperty<String>('URL', url)],
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final cacheDir = Directory('${Directory.systemTemp.path}/pcx_carto_tiles');
    final file = File('${cacheDir.path}/$cacheKey');

    // 1. If cached on local disk, load immediately (offline ready)
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 500) {
          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          return await decode(buffer);
        }
      }
    } catch (_) {}

    // 2. Fetch from network
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'PcxTelemetryApp/1.0 (Linux; Android)');
      final response = await request.close();

      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        if (bytes.length > 500) {
          // Asynchronously persist to cache folder without blocking render
          cacheDir.create(recursive: true).then((_) {
            file.writeAsBytes(bytes).catchError((_) => file);
          }).catchError((_) => null);

          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          return await decode(buffer);
        }
      }
    } catch (_) {}

    // 3. Fallback: try reading stale cache if network failed
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          return await decode(buffer);
        }
      }
    } catch (_) {}

    throw Exception('Failed to load map tile: $url');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CachedDiskImageProvider &&
          runtimeType == other.runtimeType &&
          cacheKey == other.cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}
