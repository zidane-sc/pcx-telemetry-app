import 'package:flutter/material.dart';

class LeanAngleGauge extends StatelessWidget {
  final double currentAngle; // Negative = Left, Positive = Right
  final double maxLeft;
  final double maxRight;

  const LeanAngleGauge({
    super.key,
    required this.currentAngle,
    this.maxLeft = 0.0,
    this.maxRight = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final double angle = currentAngle.clamp(-50.0, 50.0);
    final String sideLabel = angle < -1.2
        ? 'LEFT'
        : (angle > 1.2 ? 'RIGHT' : 'UPRIGHT');

    final Color activeColor = angle.abs() > 40.0
        ? Colors.redAccent
        : (angle.abs() > 25.0 ? const Color(0xFFFFB300) : const Color(0xFF00FF66));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1017),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
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
                  color: Colors.white.withOpacity(0.4),
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
                  color: Colors.white.withOpacity(0.4),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeanGaugePainter extends CustomPainter {
  final double angle; // -50 to +50
  final double maxLeft;
  final double maxRight;
  final Color color;

  _LeanGaugePainter({
    required this.angle,
    required this.maxLeft,
    required this.maxRight,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final centerX = size.width / 2;
    final halfWidth = size.width / 2;

    // 1. Background Track
    final trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(12, centerY),
      Offset(size.width - 12, centerY),
      trackPaint,
    );

    // 2. Degree Tick Marks (-45, -30, -15, 0, 15, 30, 45)
    final tickPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 1.0;

    for (int deg = -45; deg <= 45; deg += 15) {
      final x = centerX + (deg / 50.0) * (halfWidth - 14);
      final tickHeight = (deg == 0) ? 12.0 : 6.0;
      canvas.drawLine(
        Offset(x, centerY - tickHeight / 2),
        Offset(x, centerY + tickHeight / 2),
        deg == 0
            ? (Paint()
              ..color = const Color(0xFF00E5FF).withOpacity(0.7)
              ..strokeWidth = 2.0)
            : tickPaint,
      );
    }

    // 3. Peak Markers
    if (maxLeft > 2.0) {
      final leftX = centerX - (maxLeft.clamp(0.0, 50.0) / 50.0) * (halfWidth - 14);
      final peakPaint = Paint()..color = const Color(0xFFFFB300).withOpacity(0.6)..strokeWidth = 1.5;
      canvas.drawLine(Offset(leftX, centerY - 5), Offset(leftX, centerY + 5), peakPaint);
    }
    if (maxRight > 2.0) {
      final rightX = centerX + (maxRight.clamp(0.0, 50.0) / 50.0) * (halfWidth - 14);
      final peakPaint = Paint()..color = const Color(0xFFFFB300).withOpacity(0.6)..strokeWidth = 1.5;
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
