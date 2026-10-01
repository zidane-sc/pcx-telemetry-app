import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../ui/common/cyber_map_tiles.dart';

class DownloadProgress {
  final int downloaded;
  final int total;
  final bool isCompleted;
  final bool isError;
  final String statusText;

  const DownloadProgress({
    required this.downloaded,
    required this.total,
    this.isCompleted = false,
    this.isError = false,
    this.statusText = '',
  });

  double get percent => total > 0 ? (downloaded / total).clamp(0.0, 1.0) : 0.0;
}

class OfflineMapDownloader {
  static final OfflineMapDownloader _instance = OfflineMapDownloader._internal();
  factory OfflineMapDownloader() => _instance;
  OfflineMapDownloader._internal();

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  // Jabodetabek bounds
  static const double latMin = -6.65; // Bogor
  static const double latMax = -6.05; // Jakarta Utara
  static const double lonMin = 106.60; // Tangerang
  static const double lonMax = 107.05; // Bekasi

  Point<int> _deg2num(double latDeg, double lonDeg, int zoom) {
    final latRad = latDeg * (pi / 180.0);
    final n = pow(2.0, zoom);
    final xtile = ((lonDeg + 180.0) / 360.0 * n).floor();
    final ytile = ((1.0 - (log(tan(latRad) + 1.0 / cos(latRad)) / pi)) / 2.0 * n).floor();
    return Point(xtile, ytile);
  }

  Future<void> downloadJabodetabekOfflineMap() async {
    if (_isDownloading) return;
    _isDownloading = true;

    final cacheDir = Directory('${Directory.systemTemp.path}/pcx_carto_tiles');
    await cacheDir.create(recursive: true);

    final List<Map<String, dynamic>> tilesToFetch = [];

    // Zoom levels 11, 12, 13 (covers arterial highways, main roads, city streets)
    for (final z in [11, 12, 13]) {
      final p1 = _deg2num(latMax, lonMin, z);
      final p2 = _deg2num(latMin, lonMax, z);

      final minX = min(p1.x, p2.x);
      final maxX = max(p1.x, p2.x);
      final minY = min(p1.y, p2.y);
      final maxY = max(p1.y, p2.y);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tilesToFetch.add({'z': z, 'x': x, 'y': y});
        }
      }
    }

    final total = tilesToFetch.length;
    int downloaded = 0;

    _progressController.add(DownloadProgress(
      downloaded: 0,
      total: total,
      statusText: 'Menghubungkan ke server CARTO ($total tile)...',
    ));

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..maxConnectionsPerHost = 6;

    final subdomains = ['a', 'b', 'c', 'd'];

    // Concurrent batch download (6 workers)
    const int batchSize = 6;
    for (int i = 0; i < tilesToFetch.length; i += batchSize) {
      if (!_isDownloading) break;

      final chunk = tilesToFetch.sublist(
        i,
        min(i + batchSize, tilesToFetch.length),
      );

      await Future.wait(chunk.map((t) async {
        final z = t['z'];
        final x = t['x'];
        final y = t['y'];
        final cacheKey = '${z}_${x}_$y.png';
        final file = File('${cacheDir.path}/$cacheKey');

        if (await file.exists()) {
          downloaded++;
          return;
        }

        final sub = subdomains[(x + y) % subdomains.length];
        final url =
            'https://$sub.basemaps.cartocdn.com/dark_all/$z/$x/$y@2x.png?key=${CyberMapTiles.cartoApiKey}';

        try {
          final req = await client.getUrl(Uri.parse(url));
          req.headers.set('User-Agent', 'PcxTelemetryApp/1.0 (Linux; Android)');
          final resp = await req.close();
          if (resp.statusCode == 200) {
            final bytes = await consolidateHttpClientResponseBytes(resp);
            if (bytes.length > 500) {
              await file.writeAsBytes(bytes);
            }
          }
        } catch (_) {}

        downloaded++;
      }));

      _progressController.add(DownloadProgress(
        downloaded: downloaded,
        total: total,
        statusText: 'Mengunduh tile: $downloaded / $total',
      ));
    }

    client.close();
    _isDownloading = false;

    _progressController.add(DownloadProgress(
      downloaded: total,
      total: total,
      isCompleted: true,
      statusText: 'Peta offline Jabodetabek ($total tile) siap digunakan!',
    ));
  }

  void cancelDownload() {
    _isDownloading = false;
  }
}
