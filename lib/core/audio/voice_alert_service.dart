import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voice sink for the whole app.
///
/// Sprint 1 moved every telemetry threshold out of this class and into
/// [RuleService] (Trigger→Action rules). Before that, `checkSafetyLimits` and
/// `checkTelemetryThresholds` hard-coded four thresholds here, which meant a
/// rider could not retune a single one and there was no single place to audit
/// what the app warns about. Those two methods are gone: the rule engine
/// evaluates the same conditions (with hysteresis the old code lacked) and
/// calls [speakAlert] on the rules that fire.
///
/// What remains here is only the transport: TTS invocation and per-key cooldown.
class VoiceAlertService {
  static final VoiceAlertService _instance = VoiceAlertService._internal();
  factory VoiceAlertService() => _instance;
  VoiceAlertService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.zidane-sc/pcx_telemetry_app/tts');

  final Map<String, DateTime> _cooldownMap = {};

  bool isVoiceAlertEnabled = true;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isVoiceAlertEnabled = prefs.getBool('voice_alert_enabled') ?? true;
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
}