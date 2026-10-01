import 'dart:math' as math;

/// A saved route the rider can lap.
///
/// Built from a completed trip, not hand-placed. The rider rides it once,
/// saves it, and from then on the app recognises it and times laps.
class Circuit {
  final String id;
  final String name;

  /// Where the rider starts/finishes. A lap crossing this point counts.
  final double startLat, startLng;

  /// Extra radius around the start line, in metres.
  ///
  /// At 5 Hz a rider covers ~3.3 m per fix, so a bare point would let a lap
  /// trigger twice — once approaching, once leaving. The corridor exists to
  /// make "crossing" mean the same thing in both directions.
  final double startRadiusM;

  /// Geofence corners. A lap only counts if the rider stayed roughly inside,
  /// which rejects a pass-by-the-start-line that was not a real lap.
  final List<LatLngPoint> points;

  final double lengthM;

  const Circuit({
    required this.id,
    required this.name,
    required this.startLat,
    required this.startLng,
    this.startRadiusM = 40.0,
    required this.points,
    required this.lengthM,
  });

  /// Whether a fix sits inside the start corridor.
  bool isInsideStartGate(LatLngPoint p) =>
      haversineM(startLat, startLng, p.lat, p.lng) <= startRadiusM;
}

class LatLngPoint {
  final double lat, lng;
  const LatLngPoint(this.lat, this.lng);
}

/// One completed lap.
class LapResult {
  final int lapNumber;
  final Duration duration;
  final double distanceM;

  /// Boundary times within the lap. Empty when the lap has no splits.
  final List<SectorTime> sectors;

  const LapResult({
    required this.lapNumber,
    required this.duration,
    required this.distanceM,
    this.sectors = const [],
  });

  double get avgSpeedKmh =>
      duration.inMilliseconds <= 0
          ? 0.0
          : (distanceM / 1000.0) / (duration.inMilliseconds / 3600000.0);
}

class SectorTime {
  final int sectorNumber;
  final Duration time;
  const SectorTime(this.sectorNumber, this.time);
}

/// Live state of lap detection against a circuit.
enum LapState {
  /// Not started: the rider is inside the gate but the first lap needs a
  /// full departure.
  standing,

  /// The rider is away from the gate and the lap is running.
  running,

  /// The rider has crossed the gate and the lap is complete.
  complete,
}

/// Counts laps on a saved circuit.
///
/// The hard part is not the stopwatch, it is deciding where a lap begins and
/// ends. Three rules, each learned from how a real session behaves:
///
/// 1. **Arming** — the first crossing starts the clock, but only if the rider
///    has already left the gate. Otherwise the app arms mid-corner and the
///    rider's actual start is lost.
/// 2. **Direction** — a lap must be a *departure then return*, not a loop
///    around a marker twice. A flag requires crossing the gate outbound and
///    then inbound.
/// 3. **Containment** — a crossing outside the circuit's footprint is a pass,
///    not a lap. Otherwise a rider who stops at the corner shop on the same
///    street "laps" the circuit.
///
/// `ponytail:` no magnetic-lap-timer mode and no sector triggers from the UI.
/// A real track needs beacons placed by hand; a saved GPS circuit is what a
/// phone can honestly do.
class LapCounter {
  final Circuit circuit;

  /// Ignore crossings closer together than this, to stop GPS jitter at the
  /// line from counting twice.
  static const Duration debounce = Duration(seconds: 3);

  /// A lap shorter than this is not a lap. A rider cannot leave a 40 m gate,
  /// travel a circuit, and return inside a few seconds — so anything that fast
  /// is the bike sitting in the corridor while GPS jitters across the line.
  ///
  /// This, not the debounce, is what actually stops the jitter case. The
  /// debounce only guards repeated crossings while a crossing is still
  /// remembered, and the outbound transition deliberately forgets it to allow a
  /// genuine immediate return. Without a minimum lap time, that forget is a
  /// loophole a stationary bike walks straight through.
  static const Duration minLapTime = Duration(seconds: 15);

  /// The rider must have travelled this far before a return crossing counts.
  /// Pausing just past the line and rolling back in is not a lap either, and
  /// distance is harder to fake with jitter than time is.
  static const double minLapDistanceM = 200.0;

  final List<LapResult> _laps = [];
  List<LapResult> get laps => List.unmodifiable(_laps);

  LapState _state = LapState.standing;
  LapState get state => _state;

  DateTime? _lapStartAt;
  DateTime? _lastGateCrossing;
  int _lapNumber = 0;

  double? get currentLapSeconds => _lapStartAt == null
      ? null
      : DateTime.now().difference(_lapStartAt!).inMilliseconds / 1000.0;

  LapCounter(this.circuit);

  /// Feeds one GPS fix. Returns a completed [LapResult] when this fix closed a
  /// lap, otherwise null.
  ///
  /// [now] is injected so the timing is testable without a real clock.
  LapResult? update({
    required DateTime now,
    required double lat,
    required double lng,
    required double speedKmh,
  }) {
    final point = LatLngPoint(lat, lng);
    final atGate = circuit.isInsideStartGate(point);

    // Debounce: two fixes inside the corridor within 3 s is one crossing with
    // jitter, not two crossings.
    final lastCross = _lastGateCrossing;
    if (atGate && lastCross != null && now.difference(lastCross) < debounce) {
      return null;
    }

    // Accumulate distance on EVERY fix, including the ones inside the gate
    // corridor. Doing this after the gate logic lost the first and last leg of
    // every lap, because the step from the line out to the first outside fix
    // never got counted.
    if (_state == LapState.running || _lapStartAt != null) {
      final prev = _lastPoint;
      if (prev != null) {
        final step = haversineM(prev.lat, prev.lng, lat, lng);
        // Reject teleport jumps (> 60 m/s is faster than any motorcycle).
        final maxStep = 60.0 * _dtSeconds(now);
        if (step < maxStep) {
          _accumulatedM += step;
        }
      }
    }
    _lastPoint = point;
    _lastTickAt = now;

    if (atGate) {
      if (_state == LapState.running) {
        // Return leg. Three conditions must all hold for this to be a lap:
        // enough time has passed, enough ground has been covered, and the
        // rider genuinely left. The first two are what make the outbound
        // "forget the crossing" above safe.
        final start = _lapStartAt!;
        final elapsed = now.difference(start);
        final tooFast = elapsed < minLapTime;
        final tooShort = _accumulatedM < minLapDistanceM;

        if (tooFast || tooShort) {
          // Rejected: re-arm from here rather than restarting the clock, so a
          // bike circling slowly just past the line eventually completes one
          // real lap instead of never recording anything.
          _state = LapState.standing;
          _lapStartAt = now;
          _accumulatedM = 0.0;
          _lastGateCrossing = now;
          return null;
        }

        _lapNumber++;
        final lap = LapResult(
          lapNumber: _lapNumber,
          duration: elapsed,
          distanceM: _accumulatedM,
        );
        _laps.add(lap);
        // Immediately ready for the next departure: the rider is standing at
        // the line again.
        _state = LapState.standing;
        _lapStartAt = now;
        _accumulatedM = 0.0;
        _lastGateCrossing = now;
        return lap;
      }
      // Standing at the gate: arm on the way out, but only once.
      if (_state == LapState.standing) {
        _state = LapState.standing;
        _lapStartAt = now;
        _accumulatedM = 0.0;
        _lastGateCrossing = now;
      }
      return null;
    }

    // Outside the gate.
    if (_state == LapState.standing && _lapStartAt != null) {
      _state = LapState.running;
      _lastGateCrossing = null; // allow an immediate legitimate return
    }
    return null;
  }

  double _accumulatedM = 0.0;
  LatLngPoint? _lastPoint;
  DateTime? _lastTickAt;

  double _dtSeconds(DateTime now) {
    final last = _lastTickAt;
    if (last == null) return 1.0;
    final dt = now.difference(last).inMilliseconds / 1000.0;
    return dt <= 0 ? 1.0 : dt;
  }

  /// Clears laps but keeps the circuit.
  void reset() {
    _laps.clear();
    _state = LapState.standing;
    _lapNumber = 0;
    _lapStartAt = null;
    _lastGateCrossing = null;
    _accumulatedM = 0.0;
    _lastPoint = null;
    _lastTickAt = null;
  }

  LapResult? get bestLap {
    if (_laps.isEmpty) return null;
    return _laps.reduce((a, b) => a.duration <= b.duration ? a : b);
  }
}

/// Great-circle distance in metres. Shared so the circuit builder and the
/// counter cannot disagree about what "40 m from the line" means.
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const earthR = 6371008.8;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * earthR * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Derives a [Circuit] from a finished trip.
///
/// The start line is placed at the trip's **first** fix, not its midpoint or
/// its highest-lean point: a rider records a lap by starting the timer, so the
/// start of the recording is the start of the lap. Placing it anywhere else
/// produces a circuit that "works" but times the wrong arc.
Circuit circuitFromTrip({
  required String id,
  required String name,
  required List<LatLngPoint> fixPoints,
  double startRadiusM = 40.0,
}) {
  if (fixPoints.length < 2) {
    throw ArgumentError.value(
        fixPoints.length, 'fixPoints', 'need at least two fixes for a circuit');
  }

  var length = 0.0;
  for (var i = 1; i < fixPoints.length; i++) {
    length += haversineM(
      fixPoints[i - 1].lat,
      fixPoints[i - 1].lng,
      fixPoints[i].lat,
      fixPoints[i].lng,
    );
  }

  return Circuit(
    id: id,
    name: name,
    startLat: fixPoints.first.lat,
    startLng: fixPoints.first.lng,
    startRadiusM: startRadiusM,
    points: fixPoints,
    lengthM: length,
  );
}

/// One sample inside a lap, used for sector splitting.
class LapSample {
  final Duration t;
  final LatLngPoint p;
  final double speedKmh;
  const LapSample(this.t, this.p, this.speedKmh);
}

/// Analyses a lap into sectors by finding the samples nearest each time
/// fraction.
///
/// Splitting by time fraction rather than by index means the boundaries land
  /// where the rider actually was at that moment, which is what makes a sector
  /// time comparable between laps. A pure index split would put the boundary
  /// wherever the adaptive keyframer happened to place a point, so a slow lap
  /// and a fast lap would have their sectors cut in different places.
List<SectorTime> splitIntoSectors(
  List<LapSample> samples, {
  int sectorCount = 3,
}) {
  if (samples.length < sectorCount + 1) return const [];

  final totalDuration = samples.last.t.inMilliseconds -
      samples.first.t.inMilliseconds;
  if (totalDuration <= 0) return const [];

  final boundaries = <int>[];
  for (var s = 1; s < sectorCount; s++) {
    final targetMs = totalDuration * s ~/ sectorCount;
    int bestIdx = 0;
    int bestDelta = 1 << 62;
    for (var i = 0; i < samples.length; i++) {
      final delta = (samples[i].t.inMilliseconds - targetMs).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIdx = i;
      }
    }
    boundaries.add(bestIdx);
  }
  boundaries.sort();

  final sectors = <SectorTime>[];
  var prevIdx = 0;
  for (var s = 0; s < boundaries.length; s++) {
    final endIdx = boundaries[s];
    final dur = Duration(
        milliseconds: samples[endIdx].t.inMilliseconds -
            samples[prevIdx].t.inMilliseconds);
    if (dur.inMilliseconds > 0) {
      sectors.add(SectorTime(s + 1, dur));
    }
    prevIdx = endIdx;
  }
  final last = Duration(
      milliseconds: samples.last.t.inMilliseconds -
          samples[prevIdx].t.inMilliseconds);
  if (last.inMilliseconds > 0) {
    sectors.add(SectorTime(sectors.length + 1, last));
  }
  return sectors;
}