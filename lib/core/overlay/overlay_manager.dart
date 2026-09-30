import 'dart:convert';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayManager {
  static final OverlayManager _instance = OverlayManager._internal();
  factory OverlayManager() => _instance;
  OverlayManager._internal();

  bool _isOverlayOpen = false;
  bool get isOverlayOpen => _isOverlayOpen;

  Future<bool> checkPermission() async {
    return await FlutterOverlayWindow.isPermissionGranted();
  }

  Future<bool?> requestPermission() async {
    return await FlutterOverlayWindow.requestPermission();
  }

  Future<void> showFloatingOverlay({
    required double dteKm,
    required double kml,
    required double ectC,
  }) async {
    final bool hasPermission = await checkPermission();
    if (!hasPermission) {
      await requestPermission();
      return;
    }

    if (!await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: "PCX Telemetry HUD",
        overlayContent: "Monitoring performa PCX 160",
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        height: 140,
        width: 750,
      );
      _isOverlayOpen = true;
    }

    updateTelemetryData(dteKm: dteKm, kml: kml, ectC: ectC);
  }

  void updateTelemetryData({
    required double dteKm,
    required double kml,
    required double ectC,
  }) {
    FlutterOverlayWindow.shareData(
      jsonEncode({
        'dteKm': dteKm,
        'kml': kml,
        'ectC': ectC,
      }),
    );
  }

  Future<void> closeOverlay() async {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
      _isOverlayOpen = false;
    }
  }
}
