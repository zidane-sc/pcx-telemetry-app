class CvtSlipResult {
  final bool isSlipping;
  final double rpmSpeedRatio;
  final String message;

  const CvtSlipResult({
    required this.isSlipping,
    required this.rpmSpeedRatio,
    required this.message,
  });
}

class CvtSlipDetector {
  int _consecutiveSlipTicks = 0;
  static const int _slipThresholdTicks = 5; // ~2.5 seconds at 2Hz

  CvtSlipResult evaluate({
    required double rpm,
    required double speedKmh,
    required double tpsPercent,
  }) {
    if (speedKmh < 15.0 || tpsPercent < 35.0) {
      _consecutiveSlipTicks = 0;
      return const CvtSlipResult(
        isSlipping: false,
        rpmSpeedRatio: 0.0,
        message: 'Normal',
      );
    }

    final double ratio = rpm / speedKmh;

    // For PCX 160: High RPM (>7000) with low vehicle speed (<40 km/h) under throttle:
    // Ratio > 170 typically indicates belt slip or worn clutch shoes
    if (ratio > 175.0 && rpm > 6500.0) {
      _consecutiveSlipTicks++;
    } else {
      _consecutiveSlipTicks = 0;
    }

    final bool slipping = _consecutiveSlipTicks >= _slipThresholdTicks;
    return CvtSlipResult(
      isSlipping: slipping,
      rpmSpeedRatio: ratio,
      message: slipping
          ? 'CVT Slip Terdeteksi! V-Belt aus atau kampas ganda licin.'
          : 'Transmisi Normal',
    );
  }
}
