import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceAlertService {
  static final VoiceAlertService _instance = VoiceAlertService._internal();
  factory VoiceAlertService() => _instance;
  VoiceAlertService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.zidane-sc/pcx_telemetry_app/tts');

  final Map<String, DateTime> _cooldownMap = {};

  bool isVoiceAlertEnabled = true;
  double speedLimitThreshold = 90.0;
  double leanLimitThreshold = 42.0;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isVoiceAlertEnabled = prefs.getBool('voice_alert_enabled') ?? true;
      speedLimitThreshold = prefs.getDouble('speed_limit_threshold') ?? 90.0;
      leanLimitThreshold = prefs.getDouble('lean_limit_threshold') ?? 42.0;
    } catch (_) {}
  }

  Future<void> speakAlert(String message, {int cooldownSeconds = 15, String? alertKey}) async {
    if (!isVoiceAlertEnabled) return;

    final key = alertKey ?? message;
    final now = DateTime.now();
    final lastTime = _cooldownMap[key];

    if (lastTime != null && now.difference(lastTime).inSeconds < cooldownSeconds) {
      return;
    }

    _cooldownMap[key] = now;
    debugPrint('[VoiceAlert] Speaking: $message');

    try {
      await _channel.invokeMethod('speak', {'text': message});
    } catch (e) {
      debugPrint('[VoiceAlert] Native TTS invoke failed: $e');
    }
  }

  void checkSafetyLimits({
    required double speedKmh,
    required double leanAngleDeg,
    required double ectC,
    required double batteryVoltage,
    required bool isBike,
  }) {
    if (!isVoiceAlertEnabled) return;

    // 1. Lean Limit Warning (Avoid scraping exhaust / centerstand on PCX 160)
    if (isBike && leanAngleDeg.abs() >= leanLimitThreshold) {
      speakAlert(
        'Perhatian, rebah maksimal ${leanAngleDeg.abs().toStringAsFixed(0)} derajat!',
        cooldownSeconds: 20,
        alertKey: 'lean_limit',
      );
    }

    // 2. High Speed Chime
    if (speedKmh >= speedLimitThreshold) {
      speakAlert(
        'Kecepatan melebihi ${speedLimitThreshold.toStringAsFixed(0)} kilometer per jam!',
        cooldownSeconds: 45,
        alertKey: 'speed_limit',
      );
    }

    // 3. Engine Overheat Warning
    if (ectC >= 102.0) {
      speakAlert(
        'Peringatan, suhu radiator kritis ${ectC.toStringAsFixed(0)} derajat celcius!',
        cooldownSeconds: 30,
        alertKey: 'overheat',
      );
    }

    // 4. Low Battery Drop
    if (batteryVoltage > 6.0 && batteryVoltage < 11.7) {
      speakAlert(
        'Peringatan, tegangan aki drop ${batteryVoltage.toStringAsFixed(1)} volt!',
        cooldownSeconds: 60,
        alertKey: 'low_batt',
      );
    }
  }

  void checkTelemetryThresholds({
    required double ectC,
    required double batteryVoltage,
    required double dteKm,
    bool isObdConnected = false,
  }) {
    if (!isObdConnected || !isVoiceAlertEnabled) return;

    if (ectC > 102.0) {
      speakAlert(
        'Peringatan, suhu radiator kritis ${ectC.toStringAsFixed(0)} derajat celcius!',
        cooldownSeconds: 30,
        alertKey: 'overheat',
      );
    } else if (batteryVoltage < 11.8 && batteryVoltage > 6.0) {
      speakAlert(
        'Peringatan, tegangan aki drop ${batteryVoltage.toStringAsFixed(1)} volt!',
        cooldownSeconds: 60,
        alertKey: 'low_batt',
      );
    } else if (dteKm > 0.0 && dteKm < 15.0) {
      speakAlert(
        'Bensin kritis! Sisa jarak kurang dari 15 kilometer.',
        cooldownSeconds: 120,
        alertKey: 'low_fuel',
      );
    }
  }
}
