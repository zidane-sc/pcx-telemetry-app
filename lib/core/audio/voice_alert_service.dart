import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VoiceAlertService {
  static final VoiceAlertService _instance = VoiceAlertService._internal();
  factory VoiceAlertService() => _instance;
  VoiceAlertService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.zidane.pcx_telemetry_app/tts');

  DateTime? _lastAlertTime;
  String? _lastAlertMessage;

  Future<void> init() async {
    // Initialized native TTS
  }

  Future<void> speakAlert(String message, {int cooldownSeconds = 12}) async {
    final now = DateTime.now();
    if (_lastAlertTime != null && _lastAlertMessage == message) {
      if (now.difference(_lastAlertTime!).inSeconds < cooldownSeconds) {
        return;
      }
    }

    _lastAlertTime = now;
    _lastAlertMessage = message;
    debugPrint('[VoiceAlert] Speaking: $message');

    try {
      await _channel.invokeMethod('speak', {'text': message});
    } catch (e) {
      debugPrint('[VoiceAlert] Native TTS invoke failed: $e');
    }
  }

  void checkTelemetryThresholds({
    required double ectC,
    required double batteryVoltage,
    required double dteKm,
    bool isObdConnected = false,
  }) {
    if (!isObdConnected) return;

    if (ectC > 102.0) {
      speakAlert(
          "Peringatan, suhu radiator kritis ${ectC.toStringAsFixed(0)} derajat celcius!");
    } else if (batteryVoltage < 11.8 && batteryVoltage > 6.0) {
      speakAlert(
          "Peringatan, tegangan aki drop ${batteryVoltage.toStringAsFixed(1)} volt!");
    } else if (dteKm > 0.0 && dteKm < 15.0) {
      speakAlert("Bensin kritis! Sisa jarak kurang dari 15 kilometer.");
    }
  }
}
