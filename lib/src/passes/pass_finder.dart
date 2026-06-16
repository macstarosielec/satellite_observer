// Internal L3 pass-finder: the coarse-sample + root-refine search of ADR-5.
//
// Stage 1 (coarse): sample (elevation - minElevation) on a fixed grid across
// the window; an upward sign change brackets a rise, a downward sign change
// brackets a set, and the sample grid between them brackets the elevation
// maximum (culmination).
//
// Stage 2 (refine): rise/set are refined to sub-second by bisection on the
// elevation-threshold crossing; the culmination time is refined by
// golden-section maximization of the elevation over the bracketing samples
// (ADR-5 allows quadratic interpolation or golden-section; golden-section is
// used because it stays accurate on sharply-curved high overhead passes). Each
// refined time is then re-evaluated through the supplied look-angle function so
// the emitted PassEvent carries the exact az/el/range/range-rate at that
// instant.
//
// Boundary policy: only FULLY bracketed passes are returned. A pass already in
// progress at `from` (the satellite is above minElevation at the first sample)
// has no observed rise crossing and is skipped; likewise a pass still in
// progress at `to` has no observed set crossing and is skipped. Callers who
// need an in-progress pass should widen the window. This policy is documented
// on SatelliteObserver.passes and asserted by the unit tests.

import 'package:satellite_observer/src/domain/look_angle.dart';
import 'package:satellite_observer/src/domain/pass.dart';
import 'package:satellite_observer/src/passes/root_refine.dart';

/// Finds all fully-bracketed satellite passes in `[from, to]`.
///
/// [lookAngleAt] returns the topocentric look-angle at a UTC instant (the
/// pass-finder uses its `elevationDeg`). [from] and [to] bound the search
/// window (UTC). [minElevationDeg] is the horizon threshold (ADR-8). [from]
/// must precede [to] and [sampleStep] must be positive (validated by the
/// caller / facade).
///
/// Returns passes in chronological order. See the boundary policy in this
/// file's header: passes in progress at either window edge are skipped.
List<Pass> findPasses({
  required LookAngle Function(DateTime utc) lookAngleAt,
  required DateTime from,
  required DateTime to,
  required double minElevationDeg,
  required Duration sampleStep,
}) {
  final fromUtc = from.toUtc();
  final toUtc = to.toUtc();
  final stepUs = sampleStep.inMicroseconds;

  // Coarse grid of (timeUs, elevation) covering [from, to] inclusive of both
  // endpoints. We cache elevation samples so each grid point is propagated
  // once.
  final fromUs = fromUtc.microsecondsSinceEpoch;
  final toUs = toUtc.microsecondsSinceEpoch;

  double elevationAtUs(double timeUs) {
    final dt = DateTime.fromMicrosecondsSinceEpoch(
      timeUs.round(),
      isUtc: true,
    );
    return lookAngleAt(dt).elevationDeg;
  }

  // The signed margin above the horizon: positive when the satellite is above
  // the minimum elevation. Rise = upward zero crossing, set = downward.
  double marginAtUs(double timeUs) => elevationAtUs(timeUs) - minElevationDeg;

  // Build the sample grid times (always include the exact `to` endpoint).
  final sampleTimesUs = <double>[];
  for (var t = fromUs; t < toUs; t += stepUs) {
    sampleTimesUs.add(t.toDouble());
  }
  sampleTimesUs.add(toUs.toDouble());

  final margins = [for (final t in sampleTimesUs) marginAtUs(t)];

  final passes = <Pass>[];

  // Walk the grid. Track the index of the most recent rise crossing; between a
  // rise and the following set we also track the running maximum sample.
  int? riseRefinedIndexLo; // sample index just before the rise crossing
  var inPass = false;
  var peakIdx = -1;
  var peakMargin = double.negativeInfinity;

  for (var i = 0; i < sampleTimesUs.length; i++) {
    final m = margins[i];

    if (!inPass) {
      // Looking for an upward crossing into a pass. We require a previous
      // sample that was below the threshold so the rise is observed inside the
      // window (skips passes already in progress at `from`).
      // A margin of exactly 0.0 at the very first sample (i == 0) is treated as
      // "in progress" per the boundary policy: with no prior below-threshold
      // sample there is no observed rise crossing, so no pass is emitted.
      if (i > 0 && margins[i - 1] < 0.0 && m >= 0.0) {
        inPass = true;
        riseRefinedIndexLo = i - 1;
        peakIdx = i;
        peakMargin = m;
      }
      continue;
    }

    // In a pass: track the peak and look for the downward (set) crossing.
    if (m > peakMargin) {
      peakMargin = m;
      peakIdx = i;
    }
    if (m < 0.0) {
      // Downward crossing between i-1 and i -> set. Emit a fully-bracketed
      // pass.
      final riseLo = riseRefinedIndexLo!;
      final loRise = sampleTimesUs[riseLo];
      final hiRise = sampleTimesUs[riseLo + 1];
      final riseUs = bisectCrossing(
        marginAtUs,
        loUs: loRise,
        hiUs: hiRise,
      );

      final setUs = bisectCrossing(
        marginAtUs,
        loUs: sampleTimesUs[i - 1],
        hiUs: sampleTimesUs[i],
      );

      final culminationUs = _refineCulmination(
        sampleTimesUs: sampleTimesUs,
        peakIdx: peakIdx,
        riseUs: riseUs,
        setUs: setUs,
        marginAtUs: marginAtUs,
      );

      passes.add(
        Pass(
          rise: _event(PassEventKind.rise, riseUs, lookAngleAt),
          culmination:
              _event(PassEventKind.culmination, culminationUs, lookAngleAt),
          set: _event(PassEventKind.set, setUs, lookAngleAt),
        ),
      );

      // Reset for the next pass.
      inPass = false;
      riseRefinedIndexLo = null;
      peakIdx = -1;
      peakMargin = double.negativeInfinity;
    }
  }

  // If we end the loop still `inPass`, the pass is in progress at `to`; per the
  // boundary policy it is not emitted.

  return passes;
}

// Refines the culmination time by golden-section maximization of the elevation
// margin over the bracket spanning the peak grid sample's neighbours, clamped
// to the open refined pass interval (riseUs, setUs).
//
// Golden-section evaluates the real elevation arc rather than assuming it is a
// parabola, so it is accurate even for a high overhead pass where the
// elevation-vs-time curve is sharply non-parabolic near its peak (a pure
// quadratic fit there under-reads the true maximum by ~0.05+ deg).
double _refineCulmination({
  required List<double> sampleTimesUs,
  required int peakIdx,
  required double riseUs,
  required double setUs,
  required double Function(double timeUs) marginAtUs,
}) {
  // Bracket around the peak sample, clamped into the open pass interval so the
  // culmination cannot land on or outside the refined rise/set.
  final span = setUs - riseUs;
  final eps = span * 1.0e-6; // keep strictly interior
  var lo = peakIdx - 1 >= 0 ? sampleTimesUs[peakIdx - 1] : riseUs;
  var hi =
      peakIdx + 1 < sampleTimesUs.length ? sampleTimesUs[peakIdx + 1] : setUs;
  if (lo <= riseUs) lo = riseUs + eps;
  if (hi >= setUs) hi = setUs - eps;
  if (hi <= lo) {
    // Degenerate bracket (extremely short pass) - use the interval midpoint.
    return riseUs + span / 2.0;
  }

  final estimate = goldenSectionMax(marginAtUs, aUs: lo, cUs: hi);
  return estimate.timeUs;
}

PassEvent _event(
  PassEventKind kind,
  double timeUs,
  LookAngle Function(DateTime utc) lookAngleAt,
) {
  final utc = DateTime.fromMicrosecondsSinceEpoch(
    timeUs.round(),
    isUtc: true,
  );
  return PassEvent(kind: kind, utc: utc, lookAngle: lookAngleAt(utc));
}
