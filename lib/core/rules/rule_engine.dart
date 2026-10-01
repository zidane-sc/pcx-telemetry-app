import 'trigger_rule.dart';

/// Immutable outcome of evaluating every rule once.
class RuleEvaluation {
  final List<TriggerRule> fired;

  /// Per-rule live state, for the Garasi rule editor preview.
  final Map<String, RuleState> states;

  const RuleEvaluation({required this.fired, required this.states});

  bool get isEmpty => fired.isEmpty;
}

enum RuleArmState {
  /// Condition not met.
  clear,

  /// Condition met but not yet held for `holdMs`.
  pending,

  /// Condition met and held — eligible to fire, subject to cooldown.
  armed,
}

class RuleState {
  final RuleArmState armState;
  final DateTime? conditionSince;
  final DateTime? lastFiredAt;

  /// Value the rule read this tick. Null when the channel was unavailable
  /// (ECU channel while disconnected) — the editor shows `--` rather than 0.
  final double? currentValue;

  const RuleState({
    required this.armState,
    required this.conditionSince,
    required this.lastFiredAt,
    required this.currentValue,
  });
}

/// Evaluates [TriggerRule]s against a [RuleContext].
///
/// Stateless by design: [evaluate] takes an explicit `now` and returns new
/// state. That keeps it a pure function of (rules, context, previous state,
/// time), so every anti-machine-gun behaviour — hold, cooldown, edge detection
/// — is unit-testable without a fake clock, a Stream, or a widget tree.
///
/// `ponytail:` state lives in the caller, not here. This class is a pure
/// evaluator; [RuleEngine] owns the persistence and the ChangeNotifier.
class RuleEngine {
  final Map<String, RuleState> _states;
  final Map<String, double> _lastValues;

  RuleEngine({Map<String, RuleState>? initialStates})
      : _states = {...?initialStates},
        _lastValues = {};

  Map<String, RuleState> get states => Map.unmodifiable(_states);

  /// Rules whose condition is currently satisfied and held. The cockpit uses
  /// this to light idiot-warning indicators (dark when inactive, per TFT
  /// standard) without re-deriving anything.
  Set<String> get activeRuleIds =>
      _states.entries
          .where((e) => e.value.armState == RuleArmState.armed)
          .map((e) => e.key)
          .toSet();

  RuleEvaluation evaluate({
    required List<TriggerRule> rules,
    required RuleContext ctx,
    required DateTime now,
  }) {
    final fired = <TriggerRule>[];
    final nextStates = <String, RuleState>{};
    final nextValues = <String, double>{};

    for (final rule in rules) {
      final value = rule.channel.read(ctx);

      if (value == null) {
        // Channel unavailable. Clear any armed state so a rule cannot sit armed
        // on data that stopped arriving — reconnecting must require a fresh
        // hold, not resume a stale one.
        _states.remove(rule.id);
        _lastValues.remove(rule.id);
        nextStates[rule.id] = RuleState(
          armState: RuleArmState.clear,
          conditionSince: null,
          lastFiredAt: null,
          currentValue: null,
        );
        continue;
      }

      final previousValue = _lastValues[rule.id];
      final prior = _states[rule.id];

      final bool conditionMet = !rule.enabled
          ? false
          : rule.matches(value, previousValue: previousValue);

      RuleArmState armState;
      DateTime? conditionSince;

      if (!conditionMet) {
        armState = RuleArmState.clear;
        conditionSince = null;
      } else if (prior?.armState == RuleArmState.clear ||
          prior?.armState == null ||
          prior == null) {
        // Newly satisfied: start the hold clock.
        armState = rule.holdMs <= 0
            ? RuleArmState.armed
            : RuleArmState.pending;
        conditionSince = now;
      } else {
        // Still satisfied and the hold clock is already running.
        conditionSince = prior.conditionSince ?? now;
        final heldMs = now.difference(conditionSince).inMilliseconds;
        armState = heldMs >= rule.holdMs
            ? RuleArmState.armed
            : RuleArmState.pending;
      }

      DateTime? lastFiredAt = prior?.lastFiredAt;

      final bool canFire = rule.enabled &&
          armState == RuleArmState.armed &&
          (lastFiredAt == null ||
              now.difference(lastFiredAt).inSeconds >= rule.cooldownSec);

      if (canFire) {
        fired.add(rule);
        lastFiredAt = now;
      }

      nextStates[rule.id] = RuleState(
        armState: rule.enabled ? armState : RuleArmState.clear,
        conditionSince: conditionSince,
        lastFiredAt: lastFiredAt,
        currentValue: value,
      );
      nextValues[rule.id] = value;

      // A cooldown-blocked rule still fires once the cooldown expires while the
      // condition holds, because `canFire` re-evaluates on every tick.
    }

    // Carry forward states for rules that are no longer in the list (user
    // deleted a rule) so their cooldown history does not leak.
    for (final entry in _states.entries) {
      nextStates.putIfAbsent(entry.key, () => entry.value);
    }

    _states
      ..clear()
      ..addAll(nextStates);
    _lastValues
      ..clear()
      ..addAll(nextValues);

    return RuleEvaluation(fired: fired, states: Map.unmodifiable(nextStates));
  }

  /// Drops a rule's armed state, e.g. when the user edits its threshold so the
  /// new value must be re-held from scratch.
  void resetRule(String ruleId) {
    _states.remove(ruleId);
    _lastValues.remove(ruleId);
  }
}