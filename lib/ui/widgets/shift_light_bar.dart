import 'package:flutter/material.dart';

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
    const int totalSegments = 16;
    // Without a live ECU the RPM is unknown, so the bar shows nothing at all.
    // A shift light driven by an estimated RPM lights up when the rider is
    // not near the limiter, which trains them to ignore the one instrument
    // that matters most.
    final double normalized =
        isLive ? (rpm / maxRpm).clamp(0.0, 1.0) : 0.0;
    final int litCount = (normalized * totalSegments).round();
    final bool isRevLimit = isLive && rpm >= 8900.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1017),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRevLimit ? Colors.redAccent : Colors.white.withOpacity(0.06),
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
                          : Colors.white.withOpacity(0.06),
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
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'REV LIMIT',
                style: TextStyle(
                  color: Colors.white,
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
