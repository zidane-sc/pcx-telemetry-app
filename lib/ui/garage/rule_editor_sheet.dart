import 'package:flutter/material.dart';

import '../../core/rules/rule_engine.dart';
import '../../core/rules/rule_service.dart';
import '../../core/rules/trigger_rule.dart';
import '../theme/theme_service.dart';

/// Editor for the Trigger→Action rules.
///
/// Lives in Garasi, not the cockpit: editing thresholds at 60–100 km/h with
/// gloves on is how you crash. Garasi is the parked, deliberate context.
class RuleEditorSheet extends StatelessWidget {
  const RuleEditorSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      // Read from the caller's context, not from an instance: a static has no
      // `this`. The sheet body re-reads it for itself, so a theme change while
      // it is open still repaints it.
      backgroundColor: ThemeScope.slotOf(context).elevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const RuleEditorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Captured once here rather than read deep in the tree: the builders below
    // shadow `context` with their own, and a getter on a StatelessWidget has no
    // context member of its own to read from.
    final _slot = ThemeScope.slotOf(context);
    final svc = RuleService();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return AnimatedBuilder(
          animation: svc,
          builder: (context, _) {
            final rules = svc.rules;
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _slot.border(0.24),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Icon(Icons.tune,
                          color: _slot.accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ATURAN PERINGATAN',
                          style: TextStyle(
                            color: _slot.text,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kembalikan ke bawaan',
                        icon: Icon(Icons.restart_alt,
                            color: _slot.dim(0.54), size: 20),
                        onPressed: () => svc.resetToDefaults(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Ambang default meniru batas lama. Ubah sesuai gaya ridingmu.',
                    style: TextStyle(color: _slot.dim(0.38), fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: rules.length,
                    itemBuilder: (_, i) => _RuleTile(rule: rules[i]),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

}

class _RuleTile extends StatelessWidget {
  final TriggerRule rule;
  const _RuleTile({required this.rule});

  String get _unit {
    switch (rule.channel) {
      case RuleChannel.speedKmh:
      case RuleChannel.gpsSpeedKmh:
      case RuleChannel.dteKm:
        return 'km/h';
      case RuleChannel.leanAngleDeg:
      case RuleChannel.slopePercent:
        return '°';
      case RuleChannel.ectC:
      case RuleChannel.iatC:
        return '°C';
      case RuleChannel.batteryVoltage:
        return 'V';
      case RuleChannel.tpsPercent:
        return '%';
      case RuleChannel.gForce:
        return 'g';
      case RuleChannel.fuelFlowLh:
        return 'L/jam';
      case RuleChannel.instantaneousKml:
        return 'km/L';
      case RuleChannel.rpm:
        return 'rpm';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Captured once here rather than read deep in the tree: the builders below
    // shadow `context` with their own, and a getter on a StatelessWidget has no
    // context member of its own to read from.
    final _slot = ThemeScope.slotOf(context);
    final svc = RuleService();
    final state = svc.stateOf(rule.id);
    final value = state?.currentValue;
    final armed = state?.armState == RuleArmState.armed;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: armed ? _slot.danger.withOpacity(0.1) : _slot.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: armed ? _slot.danger : _slot.border(0.1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.label,
                  style: TextStyle(
                    color: rule.enabled ? _slot.text : _slot.dim(0.3),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${rule.channel.name} ${rule.op.label} '
                      '${rule.threshold.toStringAsFixed(rule.threshold % 1 == 0 ? 0 : 1)} $_unit',
                      style: TextStyle(
                          color: _slot.accent, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    // Honest about provenance: `--` when the channel has no
                    // live value, never a fake 0.
                    Text(
                      '· ${value == null ? '--' : value.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: value == null ? _slot.border(0.24) : _slot.dim(0.54),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'tahan ${rule.holdMs}ms · ulang tiap ${rule.cooldownSec}s',
                  style: TextStyle(color: _slot.border(0.24), fontSize: 9),
                ),
              ],
            ),
          ),
          _Stepper(
            value: rule.threshold,
            unit: _unit,
            enabled: rule.enabled,
            onChanged: (v) => svc.upsert(rule.copyWith(threshold: v)),
          ),
          Switch(
            value: rule.enabled,
            activeColor: _slot.accent,
            onChanged: (v) => svc.setEnabled(rule.id, v),
          ),
        ],
      ),
    );
  }

}

/// Coarse +/- stepper sized for gloved hands. Fine adjustment (0.1 steps) lives
/// in the edit dialog; on a handlebar mount, coarse beats precise.
class _Stepper extends StatelessWidget {
  final double value;
  final String unit;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _Stepper({
    required this.value,
    required this.unit,
    required this.enabled,
    required this.onChanged,
  });

  double get _step {
    if (value >= 5000) return 100; // RPM
    if (value >= 100) return 5;
    if (value >= 10) return 1;
    return 0.5;
  }

  @override
  Widget build(BuildContext context) {
    // Captured once here rather than read deep in the tree: the builders below
    // shadow `context` with their own, and a getter on a StatelessWidget has no
    // context member of its own to read from.
    final _slot = ThemeScope.slotOf(context);
    final col = enabled ? _slot.dim(0.7) : _slot.border(0.24);
    final border = _slot.border(0.06);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(Icons.remove, () => onChanged((value - _step).clamp(0.0, 20000.0)), col, border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '${value.toStringAsFixed(_step < 1 ? 1 : 0)}',
            style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
        _btn(Icons.add, () => onChanged(value + _step), col, border),
      ],
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap, Color col, Color border) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: border,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: col),
      ),
    );
  }

}