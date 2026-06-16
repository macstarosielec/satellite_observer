// Internal L3 helpers: refine a bracketed elevation-threshold crossing to a
// sub-second time (bisection), and refine a bracketed elevation maximum to its
// peak time (golden-section search). Pure functions, library-private.
//
// Times are represented as microseconds-since-epoch doubles so the refiners
// operate on a plain real axis; the pass-finder converts back to DateTime.
// Working in microseconds keeps sub-second time resolution well within double
// precision for any realistic search window.

/// Refines the zero crossing of [f] inside the bracket `[loUs, hiUs]` (time in
/// microseconds) by bisection, returning the crossing time in microseconds.
///
/// [f] is `elevation - minElevation` as a function of time (microseconds): it
/// must have opposite signs at [loUs] and [hiUs] (a sign-changing bracket the
/// coarse sampler produced). Iterates until the bracket is narrower than
/// [toleranceUs] (default 1e5 us = 0.1 s) or [maxIterations] is reached.
///
/// Throws an [ArgumentError] if the endpoints do not bracket a sign change
/// (a programming error in the caller's bracketing).
double bisectCrossing(
  double Function(double timeUs) f, {
  required double loUs,
  required double hiUs,
  double toleranceUs = 1.0e5,
  int maxIterations = 80,
}) {
  if (hiUs <= loUs) {
    throw ArgumentError.value(hiUs, 'hiUs', 'must be greater than loUs');
  }
  var lo = loUs;
  var hi = hiUs;
  var fLo = f(lo);
  final fHi = f(hi);

  // An exact-zero endpoint is already the crossing.
  if (fLo == 0.0) return lo;
  if (fHi == 0.0) return hi;
  if (fLo.sign == fHi.sign) {
    throw ArgumentError(
      'endpoints do not bracket a sign change: '
      'f(loUs)=$fLo, f(hiUs)=$fHi',
    );
  }

  var iterations = 0;
  while (hi - lo > toleranceUs && iterations < maxIterations) {
    final mid = lo + (hi - lo) / 2.0;
    final fMid = f(mid);
    if (fMid == 0.0) return mid;
    if (fMid.sign == fLo.sign) {
      lo = mid;
      fLo = fMid;
    } else {
      hi = mid;
    }
    iterations++;
  }
  return lo + (hi - lo) / 2.0;
}

/// The outcome of refining a bracketed elevation maximum.
///
/// [timeUs] is the estimated peak time (microseconds since epoch); [value] is
/// the estimated peak value at that time.
class PeakEstimate {
  /// Creates a [PeakEstimate] at [timeUs] with peak [value].
  const PeakEstimate(this.timeUs, this.value);

  /// The estimated peak time, in microseconds since epoch.
  final double timeUs;

  /// The estimated peak value at [timeUs].
  final double value;
}

/// Maximizes a unimodal function [f] on `[aUs, cUs]` by golden-section search,
/// returning the peak time/value.
///
/// The bracket must contain a single interior maximum (the coarse sampler
/// guarantees this around its peak grid sample). It evaluates [f] directly, so
/// it converges to the real maximum of a curved arc (e.g. a high overhead pass
/// where elevation-vs-time is sharply non-parabolic, which a parabola fit would
/// miss). Iterates until the
/// bracket is narrower than [toleranceUs] (default 5e4 us = 0.05 s) or
/// [maxIterations] is reached.
///
/// Throws an [ArgumentError] if `cUs <= aUs`.
PeakEstimate goldenSectionMax(
  double Function(double timeUs) f, {
  required double aUs,
  required double cUs,
  double toleranceUs = 5.0e4,
  int maxIterations = 100,
}) {
  if (cUs <= aUs) {
    throw ArgumentError.value(cUs, 'cUs', 'must be greater than aUs');
  }
  // Golden ratio resolution: invphi = 1/phi, invphi2 = 1/phi^2.
  const invphi = 0.6180339887498949;
  const invphi2 = 0.3819660112501051;

  var a = aUs;
  var c = cUs;
  var h = c - a;
  var x1 = a + invphi2 * h;
  var x2 = a + invphi * h;
  var f1 = f(x1);
  var f2 = f(x2);

  var iterations = 0;
  while (h > toleranceUs && iterations < maxIterations) {
    if (f1 >= f2) {
      // Maximum is in [a, x2]; discard the right segment.
      c = x2;
      x2 = x1;
      f2 = f1;
      h = c - a;
      x1 = a + invphi2 * h;
      f1 = f(x1);
    } else {
      // Maximum is in [x1, c]; discard the left segment.
      a = x1;
      x1 = x2;
      f1 = f2;
      h = c - a;
      x2 = a + invphi * h;
      f2 = f(x2);
    }
    iterations++;
  }

  // Best estimate: the midpoint of the final narrow bracket, evaluated.
  final tStar = a + (c - a) / 2.0;
  return PeakEstimate(tStar, f(tStar));
}
