import 'package:flutter/material.dart';
import '../theme/theme_service.dart';

class ShiftLightBar extends StatelessWidget {
  final double rpm;
  final double maxRpm;
  final bool isLive;

  const ShiftLightBar({
    super.key,
    required this.rpm,
    this.maxRpm = 9500.0,
    this.isLive = false,
  });

  @override
  Widget build(BuildContext context) {
    final slot = ThemeScope.slotOf(context);
    const int totalSegments = 16;
    // Without a live ECU the RPM is unknown, so the bar shows nothing at all.
    // A shift light driven by an estimated RPM lights up when the rider is
    // not near the limiter, which trains them to ignore the one instrument
    // that matters most.
    final double normalized =
        isLive ? (rpm / maxRpm).clamp(0.0, 1.0) : 0.0;
    final int litCount = (normalized * totalSegments).round();
    final bool isRevLimit = isLive && rpm >= 8900.0;
    // Segment colours stay fixed: green-to-amber-to-red is the tachometer
    // convention every rider already knows, and theming it would mean a rider
    // has to relearn the bar in a new palette. The frame and the rev-limit pill
    // are chrome, so they follow the slot.

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: slot.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRevLimit ? slot.danger : slot.border(0.06),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(totalSegments, (idx) {
                final bool isLit = idx < litCount;

                Color segmentColor;
                if (idx < 8) {
                  segmentColor = const Color(0xFF00FF66); // Green (1,500 - 6,000)
                } else if (idx < 12) {
                  segmentColor = const Color(0xFFFFB300); // Amber (6,000 - 8,500)
                } else {
                  segmentColor = Colors.redAccent; // Redline (>8,500)
                }

                return Expanded(
                  child: Container(
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: isLit
                          ? segmentColor
                          : slot.border(0.06),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: isLit
                          ? [
                              BoxShadow(
                                color: segmentColor.withOpacity(0.6),
                                blurRadius: 4,
                                spreadRadius: 0.5,
                              )
                            ]
                          : null,
                    ),
                  ),
                );
              }),
            ),
          ),
          if (isRevLimit) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                // onAccent rather than a fixed white: every slot's danger fill
                // is paired with the foreground that was measured against it,
                // and Terik's deeper red needs white just as the dark slots do.
                color: slot.danger,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'REV LIMIT',
                style: TextStyle(
                  color: slot.onAccent,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
