import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import '../constants/api_constants.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  PocketBase? _pb;
  String? _userId;

  void initialize({required PocketBase pb, String? userId}) {
    _pb = pb;
    _userId = userId;

    // Attach Flutter global error catcher
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      logError(
        errorType: 'FlutterError',
        stackTrace: details.stack?.toString() ?? details.exceptionAsString(),
        deviceInfo: defaultTargetPlatform.toString(),
      );
    };

    // Platform error catcher
    PlatformDispatcher.instance.onError = (error, stack) {
      logError(
        errorType: 'PlatformUncaughtException',
        stackTrace: stack.toString(),
        deviceInfo: defaultTargetPlatform.toString(),
      );
      return true;
    };
  }

  Future<void> logError({
    required String errorType,
    required String stackTrace,
    String? deviceInfo,
  }) async {
    if (_pb == null) return;
    try {
      await _pb!.collection(ApiConstants.collectionAppLogs).create(
        body: {
          'user': _userId ?? '',
          'device_info': deviceInfo ?? 'Android',
          'error_type': errorType,
          'stack_trace': stackTrace.length > 2000
              ? stackTrace.substring(0, 2000)
              : stackTrace,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      debugPrint('[AppLogger] Error synced to PocketBase successfully.');
    } catch (e) {
      debugPrint('[AppLogger] Failed to upload error log to PocketBase: $e');
    }
  }
}
