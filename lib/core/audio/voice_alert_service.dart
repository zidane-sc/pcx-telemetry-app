import 'package:flutter_tts/flutter_tts.dart';

class VoiceAlertService {
  static final VoiceAlertService _instance = VoiceAlertService._internal();
  factory VoiceAlertService() => _instance;
  VoiceAlertService._internal();

  final FlutterTts _tts = FlutterTts();
  DateTime? _lastAlertTime;
  String? _lastAlertMessage;

  Future<void> init() async {
    try {
      await _tts.setLanguage("id-ID"); // Bahasa Indonesia
      await _tts.setSpeechRate(0.5); // Kecepatan wajar
      await _tts.setVolume(1.0); // Volume penuh untuk TWS/Helm
      await _tts.setPitch(1.0);
    } catch (_) {}
  }

  Future<void> speakAlert(String message, {int cooldownSeconds = 15}) async {
    final now = DateTime.now();
    if (_lastAlertTime != null && _lastAlertMessage == message) {
      if (now.difference(_lastAlertTime!).inSeconds < cooldownSeconds) {
        return; // Mencegah spam suara saat alarm aktif terus menerus
      }
    }

    _lastAlertTime = now;
    _lastAlertMessage = message;
    await _tts.speak(message);
  }

  void checkTelemetryThresholds({
    required double ectC,
    required double batteryVoltage,
    required double dteKm,
  }) {
    if (ectC > 102.0) {
      speakAlert("Peringatan, suhu radiator kritis ${ectC.toStringAsFixed(0)} derajat!");
    } else if (batteryVoltage < 11.8 && batteryVoltage > 6.0) {
      speakAlert("Peringatan, tegangan aki drop ${batteryVoltage.toStringAsFixed(1)} volt!");
    } else if (dteKm > 0.0 && dteKm < 15.0) {
      speakAlert("Bensin kritis! Sisa jarak kurang dari 15 kilometer.");
    }
  }
}
