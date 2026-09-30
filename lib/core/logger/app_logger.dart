import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
        errorType: 'FlutterFrameworkError',
        stackTrace: details.stack?.toString() ?? details.exceptionAsString(),
        deviceInfo: defaultTargetPlatform.toString(),
      );
    };

    // Platform async error catcher
    PlatformDispatcher.instance.onError = (error, stack) {
      logError(
        errorType: 'PlatformUncaughtException',
        stackTrace: '$error\n$stack',
        deviceInfo: defaultTargetPlatform.toString(),
      );
      return true;
    };

    // Flush any pending offline crash logs
    flushPendingLogs();
  }

  void updateUserId(String userId) {
    _userId = userId;
  }

  Future<void> logError({
    required String errorType,
    required String stackTrace,
    String? deviceInfo,
  }) async {
    final body = {
      'user': _userId ?? '',
      'device_info': deviceInfo ?? defaultTargetPlatform.toString(),
      'error_type': errorType,
      'stack_trace': stackTrace.length > 2500
          ? stackTrace.substring(0, 2500)
          : stackTrace,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (_pb == null) {
      await _cacheLogLocally(body);
      return;
    }

    try {
      await _pb!.collection(ApiConstants.collectionAppLogs).create(body: body);
      debugPrint('[AppLogger] Error report synced to PocketBase successfully.');
    } catch (e) {
      debugPrint('[AppLogger] Network error sending log to PocketBase, caching locally: $e');
      await _cacheLogLocally(body);
    }
  }

  Future<void> _cacheLogLocally(Map<String, dynamic> log) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('pending_error_logs') ?? [];
      list.add(jsonEncode(log));
      await prefs.setStringList('pending_error_logs', list);
    } catch (_) {}
  }

  Future<void> flushPendingLogs() async {
    if (_pb == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('pending_error_logs') ?? [];
      if (list.isEmpty) return;

      final remaining = <String>[];
      for (final raw in list) {
        try {
          final body = jsonDecode(raw) as Map<String, dynamic>;
          await _pb!.collection(ApiConstants.collectionAppLogs).create(body: body);
        } catch (_) {
          remaining.add(raw);
        }
      }
      await prefs.setStringList('pending_error_logs', remaining);
      debugPrint('[AppLogger] Flushed ${list.length - remaining.length} cached logs.');
    } catch (_) {}
  }
}
