import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/voice_alert_service.dart';
import 'rule_engine.dart';
import 'trigger_rule.dart';

/// What the engine decided to do. Kept separate from the engine so a test can
/// assert on decisions without a TTS channel, a MethodChannel, or SharedPreferences.
enum RuleActionType { voice, visual, journal }

class RuleAction {
  final String ruleId;
  final RuleActionType type;
  final String message;

  const RuleAction({
    required this.ruleId,
    required this.type,
    required this.message,
  });
}

/// Owns the rule list, persistence, and action dispatch.
///
/// The engine is pure ([RuleEngine]); this is the stateful shell that survives
/// across ticks, writes to SharedPreferences, and turns decisions into speech.
class RuleService extends ChangeNotifier {
  static final RuleService _instance = RuleService._internal();
  factory RuleService() => _instance;
  RuleService._internal();

  static const String _prefsKey = 'trigger_rules_v1';

  final RuleEngine _engine = RuleEngine();
  List<TriggerRule> _rules = defaultRules();
  DateTime _lastEvalAt = DateTime.now();
  final List<RuleAction> _lastActions = [];

  List<TriggerRule> get rules => List.unmodifiable(_rules);
  List<RuleAction> get lastActions => List.unmodifiable(_lastActions);
  RuleEngine get engine => _engine;

  /// Rule ids currently satisfied and held — the cockpit lights these as
  /// idiot-warning indicators.
  Set<String> get activeRuleIds => _engine.activeRuleIds;

  RuleState? stateOf(String ruleId) => _engine.states[ruleId];

  /// Defaults reproduce the thresholds that were hard-coded in
  /// `voice_alert_service.dart` before Sprint 1, so upgrading changes no
  /// behaviour. Every rider can then retune them in Garasi.
  static List<TriggerRule> defaultRules() => [
        const TriggerRule(
          id: 'lean_limit',
          label: 'Batas Rebah',
          channel: RuleChannel.leanAngleDeg,
          op: RuleOperator.greaterOrEqual,
          threshold: 42.0,
          holdMs: 800,
          cooldownSec: 20,
          voiceMessage: 'Perhatian, rebah maksimal!',
        ),
        const TriggerRule(
          id: 'speed_limit',
          label: 'Batas Kecepatan',
          channel: RuleChannel.speedKmh,
          op: RuleOperator.greaterOrEqual,
          threshold: 90.0,
          holdMs: 2000,
          cooldownSec: 45,
          voiceMessage: 'Kecepatan melebihi batas!',
        ),
        const TriggerRule(
          id: 'overheat',
          label: 'Suhu Radiator Kritis',
          channel: RuleChannel.ectC,
          op: RuleOperator.greaterOrEqual,
          threshold: 102.0,
          holdMs: 3000,
          cooldownSec: 30,
          voiceMessage: 'Peringatan, suhu radiator kritis!',
        ),
        const TriggerRule(
          id: 'low_batt',
          label: 'Tegangan Aki Drop',
          channel: RuleChannel.batteryVoltage,
          op: RuleOperator.lessThan,
          threshold: 11.7,
          holdMs: 2000,
          cooldownSec: 60,
          voiceMessage: 'Peringatan, tegangan aki drop!',
        ),
        const TriggerRule(
          id: 'low_fuel',
          label: 'Benzin Kritis',
          channel: RuleChannel.dteKm,
          op: RuleOperator.lessThan,
          threshold: 15.0,
          holdMs: 5000,
          cooldownSec: 120,
          voiceMessage: 'Bensin kritis! Sisa jarak kurang dari 15 kilometer.',
        ),
        const TriggerRule(
          id: 'redline',
          label: 'Batas Putar RPM',
          channel: RuleChannel.rpm,
          op: RuleOperator.greaterOrEqual,
          threshold: 8800.0,
          holdMs: 300,
          cooldownSec: 10,
          voiceMessage: 'Batas putar mesin! Turunkan gas!',
        ),
      ];

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey);
      if (raw == null || raw.isEmpty) {
        _rules = defaultRules();
        return;
      }
      final decoded = <TriggerRule>[];
      for (final item in raw) {
        final obj = jsonDecode(item);
        if (obj is! Map<String, dynamic>) continue;
        final rule = TriggerRule.fromJson(obj);
        // Silently drop unparseable entries instead of throwing: a corrupt
        // prefs row must never brick the cockpit.
        if (rule != null) decoded.add(rule);
      }
      _rules = decoded.isEmpty ? defaultRules() : decoded;
    } catch (_) {
      _rules = defaultRules();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefsKey,
        _rules.map((r) => jsonEncode(r.toJson())).toList(),
      );
    } catch (_) {}
  }

  /// Ticks the engine and dispatches any resulting actions.
  ///
  /// Rate-limited internally so the caller can safely invoke this on every
  /// sensor frame (15 Hz) — evaluating is cheap, but dispatching voice is not.
  void onTelemetry(RuleContext ctx, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (t.difference(_lastEvalAt).inMilliseconds < 250) return;
    _lastEvalAt = t;

    final result =
        _engine.evaluate(rules: _rules, ctx: ctx, now: t);

    if (result.isEmpty) {
      if (_lastActions.isNotEmpty) {
        _lastActions.clear();
        notifyListeners();
      }
      return;
    }

    final actions = <RuleAction>[];
    for (final rule in result.fired) {
      final action = RuleAction(
        ruleId: rule.id,
        type: RuleActionType.voice,
        message: rule.voiceMessage,
      );
      actions.add(action);
      VoiceAlertService().speakAlert(
        rule.voiceMessage,
        cooldownSeconds: rule.cooldownSec,
        alertKey: rule.id,
      );
    }

    _lastActions
      ..clear()
      ..addAll(actions);
    notifyListeners();
  }

  Future<void> upsert(TriggerRule rule) async {
    final idx = _rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      _rules[idx] = rule;
    } else {
      _rules.add(rule);
    }
    // Threshold changed: force a fresh hold so the new value cannot fire on the
    // already-armed state from the old one.
    _engine.resetRule(rule.id);
    await _persist();
    notifyListeners();
  }

  Future<void> setEnabled(String ruleId, bool enabled) =>
      upsert(_ruleById(ruleId).copyWith(enabled: enabled));

  Future<void> remove(String ruleId) async {
    _rules.removeWhere((r) => r.id == ruleId);
    _engine.resetRule(ruleId);
    await _persist();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _rules = defaultRules();
    for (final r in _rules) {
      _engine.resetRule(r.id);
    }
    await _persist();
    notifyListeners();
  }

  TriggerRule _ruleById(String id) =>
      _rules.firstWhere((r) => r.id == id, orElse: () => defaultRules().first);
}