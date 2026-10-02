import 'package:flutter/material.dart';

import '../../core/telemetry/lean_estimator.dart';
import '../theme/theme_service.dart';

class LeanAngleGauge extends StatelessWidget {
  final double currentAngle; // Negative = Left, Positive = Right
  final double maxLeft;
  final double maxRight;

  /// Sprint 2: the full reading with provenance. When null the gauge shows the
  /// IMU figure alone and labels it as unverified — it must never imply a
  /// cross-check that did not happen.
  final LeanReading? reading;

  const LeanAngleGauge({
    super.key,
    required this.currentAngle,
    this.maxLeft = 0.0,
    this.maxRight = 0.0,
    this.reading,
  });

  @override
  Widget build(BuildContext context) {
    // Captured here: the CustomPaint below is a separate widget, and a
    // StatelessWidget has no `context` member of its own.
    final _slot = ThemeScope.slotOf(context);
    final double angle = currentAngle.clamp(-50.0, 50.0);
    final String sideLabel = angle < -1.2
        ? 'LEFT'
        : (angle > 1.2 ? 'RIGHT' : 'UPRIGHT');

    final Color activeColor = angle.abs() > 40.0
        ? _slot.danger
        : (angle.abs() > 25.0 ? _slot.warning : _slot.positive);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _slot.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _slot.dim(0.08), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Labels: Left Peak, Current Digital Readout, Right Peak
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '◀ L ${maxLeft.toStringAsFixed(0)}°',
                style: TextStyle(
                  color: _slot.dim(0.4),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Text(
                    '${angle.abs().toStringAsFixed(0)}° ',
                    style: TextStyle(
                      color: activeColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    sideLabel,
                    style: TextStyle(
                      color: activeColor.withOpacity(0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Text(
                'R ${maxRight.toStringAsFixed(0)}° ▶',
                style: TextStyle(
                  color: _slot.dim(0.4),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Custom Painted Horizon Balance Bar
          SizedBox(
            height: 18,
            width: double.infinity,
            child: CustomPaint(
              painter: _LeanGaugePainter(
                angle: angle,
                maxLeft: maxLeft,
                maxRight: maxRight,
                color: activeColor,
                slot: _slot,
              ),
            ),
          ),

          // Sprint 2: provenance line. Two numbers where a single number would
          // look cleaner, because a single number here is a claim the app cannot
          // support. `degraded` states the reading is untrustworthy outright.
          if (reading != null) ...[
            const SizedBox(height: 5),
            _ProvenanceRow(reading: reading!),
          ],
        ],
      ),
    );
  }

}

/// Shows where the displayed angle came from, and whether to believe it.
class _ProvenanceRow extends StatelessWidget {
  final LeanReading reading;
  const _ProvenanceRow({required this.reading});

  @override
  Widget build(BuildContext context) {
    // Captured here: the CustomPaint below is a separate widget, and a
    // StatelessWidget has no `context` member of its own.
    final _slot = ThemeScope.slotOf(context);
    final bool degraded = reading.confidence == LeanConfidence.degraded;
    final bool dual = reading.confidence == LeanConfidence.dualSource;
    final Color tone =
        degraded ? _slot.danger : (dual ? _slot.dim(0.54) : _slot.dim(0.38));

    final TextStyle mono = TextStyle(
      color: tone,
      fontSize: 9,
      fontFamily: 'monospace',
      fontWeight: FontWeight.bold,
    );

    final gps = reading.gpsDeg;
    final camber = reading.camberDeg;

    if (gps == null) {
      // Only the IMU. Say so rather than implying a cross-check.
      return Row(
        children: [
          Text('IMU ${reading.imuDeg.abs().toStringAsFixed(0)}°', style: mono),
          const SizedBox(width: 6),
          Text(
            dual ? '' : '· GPS OFF',
            style: mono.copyWith(color: _slot.border(0.24)),
          ),
        ],
      );
    }

    return Row(
      children: [
        Text('IMU ${reading.imuDeg.abs().toStringAsFixed(0)}°', style: mono),
        const SizedBox(width: 6),
        Text(
          '· GPS ${gps.abs().toStringAsFixed(0)}°'
          '${reading.radiusM != null ? ' r=${reading.radiusM!.round()}m' : ''}',
          style: mono,
        ),
        if (camber != null && camber.abs() >= 1.0) ...[
          const SizedBox(width: 6),
          Text(
            '· CAMBER ${camber > 0 ? '+' : ''}${camber.toStringAsFixed(0)}°',
            style: mono.copyWith(
              color: degraded ? _slot.danger : _slot.dim(0.5),
            ),
          ),
        ],
        if (degraded) ...[
          const SizedBox(width: 6),
          Icon(Icons.warning_amber_rounded,
              size: 10, color: _slot.danger),
        ],
      ],
    );
  }

}

class _LeanGaugePainter extends CustomPainter {
  final double angle; // -50 to +50
  final double maxLeft;
  final double maxRight;
  final Color color;
  /// A CustomPainter has no BuildContext, so the active slot is handed in. The
  /// track and the tick marks are drawn from it: on a light background the
  /// hardcoded white tints this gauge used would be a dark smudge across the
  /// bar, and a canvas cannot ask anyone whether it looks right.
  final ThemeSlot slot;

  _LeanGaugePainter({
    required this.angle,
    required this.maxLeft,
    required this.maxRight,
    required this.color,
    required this.slot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final centerX = size.width / 2;
    final halfWidth = size.width / 2;

    // 1. Background Track
    final trackPaint = Paint()
      ..color = slot.dim(0.06)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(12, centerY),
      Offset(size.width - 12, centerY),
      trackPaint,
    );

    // 2. Degree Tick Marks (-45, -30, -15, 0, 15, 30, 45)
    final tickPaint = Paint()
      ..color = slot.dim(0.2)
      ..strokeWidth = 1.0;

    for (int deg = -45; deg <= 45; deg += 15) {
      final x = centerX + (deg / 50.0) * (halfWidth - 14);
      final tickHeight = (deg == 0) ? 12.0 : 6.0;
      canvas.drawLine(
        Offset(x, centerY - tickHeight / 2),
        Offset(x, centerY + tickHeight / 2),
        deg == 0
            ? (Paint()
              ..color = slot.accent.withOpacity(0.7)
              ..strokeWidth = 2.0)
            : tickPaint,
      );
    }

    // 3. Peak Markers
    if (maxLeft > 2.0) {
      final leftX = centerX - (maxLeft.clamp(0.0, 50.0) / 50.0) * (halfWidth - 14);
      final peakPaint = Paint()..color = slot.warning.withOpacity(0.6)..strokeWidth = 1.5;
      canvas.drawLine(Offset(leftX, centerY - 5), Offset(leftX, centerY + 5), peakPaint);
    }
    if (maxRight > 2.0) {
      final rightX = centerX + (maxRight.clamp(0.0, 50.0) / 50.0) * (halfWidth - 14);
      final peakPaint = Paint()..color = slot.warning.withOpacity(0.6)..strokeWidth = 1.5;
      canvas.drawLine(Offset(rightX, centerY - 5), Offset(rightX, centerY + 5), peakPaint);
    }

    // 4. Dynamic Filled Active Bar from Center to Angle
    final activeX = centerX + (angle / 50.0) * (halfWidth - 14);
    final fillPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(centerX, centerY), Offset(activeX, centerY), fillPaint);

    // 5. Sliding Needle / Level Bubble
    final bubblePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(Offset(activeX, centerY), 6.0, glowPaint);
    canvas.drawCircle(Offset(activeX, centerY), 4.0, bubblePaint);
  }

  @override
  bool shouldRepaint(covariant _LeanGaugePainter oldDelegate) {
    return oldDelegate.angle != angle ||
        oldDelegate.maxLeft != maxLeft ||
        oldDelegate.maxRight != maxRight ||
        oldDelegate.color != color;
  }
}
