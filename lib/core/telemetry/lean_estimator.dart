import 'dart:math';

/// How much to trust the displayed lean angle.
enum LeanConfidence {
  /// Both the IMU and the GPS-geometry estimate are available and agree
  /// within tolerance. The number can be taken at face value.
  dualSource,

  /// Only the IMU attitude estimate is available (GPS off, below minimum
  /// speed, or curvature unresolvable). The number is real but unverified —
  /// and on a soft mount or a cambered road it can be wrong by 10° or more.
  imuOnly,

  /// The two sources disagree beyond [LeanEstimator.divergenceToleranceDeg].
  /// Something is wrong: a loose mount, road camber, or rider body movement.
  /// Do not trust the reading.
  degraded,
}

/// Immutable lean-angle reading with its provenance.
class LeanReading {
  /// IMU attitude estimate. Negative = left, positive = right.
  final double imuDeg;

  /// GPS-geometry estimate from corner radius. Null when unavailable.
  final double? gpsDeg;

  /// Road camber estimate in degrees, i.e. the residual `imuDeg - gpsDeg`.
  ///
  /// A phone's IMU measures attitude relative to *gravity*, not relative to the
  /// road. On a banked corner the gauge reads lean + camber combined, so this
  /// residual is the only way to tell a rider that a 41° reading on a mountain
  /// hairpin may really be 35° of lean on a 6% crown. Null without a GPS fix.
  final double? camberDeg;

  /// Corner radius in metres used for [gpsDeg]. Null when unresolvable.
  final double? radiusM;

  final LeanConfidence confidence;

  const LeanReading({
    required this.imuDeg,
    this.gpsDeg,
    this.camberDeg,
    this.radiusM,
    required this.confidence,
  });

  /// What the gauge should show as the primary number.
  double get displayDeg => imuDeg;

  bool get hasDualSource => gpsDeg != null;
}

class LeanEstimator {
  /// Standard gravity, m/s².
  static const double g = 9.81;

  /// Below this speed the GPS radius is meaningless: a 10 m/s² jump in speed
  /// over a 3-second window yields a tiny, noisy radius, and arctan of a
  /// noisy radius is a noisy angle. Field reports put GPS-derived lean at
  /// ±2–3° with good reception — and much worse in exactly the tight corners
  /// riders care about.
  static const double minSpeedKmhForGps = 8.0;

  /// Above this the two sources have disagreed so much that something is
  /// physically wrong with the measurement, not just noisy.
  static const double divergenceToleranceDeg = 12.0;

  /// Three fixes closer than this in space are not a curve, they are noise.
  /// Below 2 m the triangle is too small for the circumcircle to be stable.
  static const double minArcLengthM = 2.0;

  /// If the three points are nearly collinear the circumradius explodes —
  /// on a straight road the "radius" is effectively infinite, which correctly
  /// yields zero lean, but with floating-point noise it yields garbage. This
  /// threshold rejects that.
  ///
  /// 0.008 corresponds to a turn angle of ~0.46°. Lower than the ~1.15° a
  /// 0.02 threshold demanded, because real 5 Hz fixes on a straight road still
  /// wander a degree or so from multipath noise — a tight cutoff reports "no
  /// curve" on every highway sweeper, which silently drops the GPS check
  /// exactly where a rider most wants it. 0.46° of turn over the ~35–150 m
  /// baseline between fixes is still far below anything a rider would call
  /// cornering.
  static const double minSineOfTurn = 0.008;

  /// GPS-derived lean angle in degrees.
  ///
  /// At steady speed through a steady-radius corner, the bike leans so that
  /// gravity and the centripetal acceleration resolve along one line, giving
  /// `tan(phi) = v² / (g·r)`. The memorable form: **45° of lean is 1.0 g of
  /// cornering force**.
  ///
  /// Returns null when the inputs cannot support an estimate.
  static double? gpsLeanDeg({
    required double speedKmh,
    required double radiusM,
  }) {
    if (radiusM == null || radiusM <= 0) return null;
    if (speedKmh < minSpeedKmhForGps) return null;

    final double v = speedKmh / 3.6; // m/s
    final double phiRad = atan((v * v) / (g * radiusM));
    final double phiDeg = phiRad * 180.0 / pi;

    if (phiDeg.isNaN || phiDeg.isInfinite) return null;
    return phiDeg.clamp(0.0, 85.0);
  }

  /// Lateral acceleration in g, the direct physical quantity a rider feels.
  ///
  /// `a_lat = v²/r`, expressed in g. At 1.0 g the bike is leaned 45° — the same
  /// quantity [gpsLeanDeg] expresses as an angle.
  static double lateralG({
    required double speedKmh,
    required double radiusM,
    }) {
      if (radiusM == null || radiusM <= 0) return 0.0;
    final double v = speedKmh / 3.6;
    return (v * v) / (radiusM * g);
  }

  /// Circumradius of the circle through three consecutive GPS fixes.
  ///
  /// Uses the standard formula `R = (a·b·c) / (4·A)` where a, b, c are the
  /// sides of the triangle and A its area. Returns null when the fixes do not
  /// describe a usable arc — too close together, or nearly collinear (a
  /// straight road).
  ///
  /// `ponytail:` planar approximation using an equirectangular projection.
  /// Adequate to a few metres over the ~10–50 m baseline between 5 Hz fixes,
  /// and it avoids pulling in a geodesy dependency. Upgrade to a proper
  /// geodesic (Vincenty / geographiclib) only if a rider shows radius error
  /// large enough to move the displayed lean by more than ~1°.
  static double? radiusFromFixes({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
    required double lat3,
    required double lon3,
  }) {
    // Equirectangular projection to metres, centred on the middle fix.
    const double earthRadiusM = 6371008.8;
    final double latRefRad = lat2 * pi / 180.0;
    final double mPerDegLat = pi * earthRadiusM / 180.0;
    final double mPerDegLon = mPerDegLat * cos(latRefRad);

    double x1 = (lon1 - lon2) * mPerDegLon;
    double y1 = (lat1 - lat2) * mPerDegLat;
    double x2 = (lon3 - lon2) * mPerDegLon;
    double y2 = (lat3 - lat2) * mPerDegLat;

    // Middle fix is the origin; side vectors.
    final double dx21 = x1 - 0.0;
    final double dy21 = y1 - 0.0;
    final double dx23 = x2 - 0.0;
    final double dy23 = y2 - 0.0;
    final double dx13 = x1 - x2;
    final double dy13 = y1 - y2;

    final double a = sqrt(dx21 * dx21 + dy21 * dy21); // P2->P1
    final double b = sqrt(dx23 * dx23 + dy23 * dy23); // P2->P3
    final double c = sqrt(dx13 * dx13 + dy13 * dy13); // P1->P3

    // Reject a degenerate baseline.
    if (a < minArcLengthM || b < minArcLengthM || c < minArcLengthM) {
      return null;
    }

    // Cross product magnitude = 2 * triangle area.
    final double cross = (dx21 * dy23 - dy21 * dx23).abs();
    final double twoArea = cross;
    if (twoArea < 1e-9) return null; // exactly collinear

    // Sine of the turn angle at the middle vertex. Nearly 1 for a sharp turn,
    // ~0 for straight. Rejecting the near-straight case avoids dividing by a
    // tiny area and reporting a huge, meaningless radius.
    final double sinTurn = twoArea / (a * b);
    if (sinTurn < minSineOfTurn) return null;

    // R = (a·b·c) / (4A), and 4A = 2 * twoArea.
    final double radius = (a * b * c) / (2.0 * twoArea);
    if (radius.isNaN || radius.isInfinite || radius <= 0) return null;
    return radius;
  }

  /// Combines both estimates into one reading with an honest confidence.
  ///
  /// [imuDeg] is always present — the IMU always reports something. [radiusM]
  /// is null whenever curvature could not be resolved, which is the signal to
  /// fall back to [LeanConfidence.imuOnly].
  static LeanReading fromSources({
    required double imuDeg,
    required double speedKmh,
    double? radiusM,
  }) {
    final double? gpsDeg =
        gpsLeanDeg(speedKmh: speedKmh, radiusM: radiusM ?? double.nan);

    if (gpsDeg == null) {
      return LeanReading(
        imuDeg: imuDeg,
        confidence: LeanConfidence.imuOnly,
      );
    }

    // Sign handling: the IMU reports left as negative, right as positive. The
    // GPS geometry estimate is a magnitude — it does not know which way the
    // bike is turning, only how hard. Compare magnitudes for divergence, and
    // apply the IMU's sign to the GPS figure so both read the same direction.
    final double imuAbs = imuDeg.abs();
    final double divergence = (imuAbs - gpsDeg).abs();
    final double signedGps = imuDeg < 0 ? -gpsDeg : gpsDeg;

    if (divergence > divergenceToleranceDeg) {
      return LeanReading(
        imuDeg: imuDeg,
        gpsDeg: signedGps,
        camberDeg: imuDeg - signedGps,
        radiusM: radiusM,
        confidence: LeanConfidence.degraded,
      );
    }

    return LeanReading(
      imuDeg: imuDeg,
      gpsDeg: signedGps,
      camberDeg: imuDeg - signedGps,
      radiusM: radiusM,
      confidence: LeanConfidence.dualSource,
    );
  }
}