// Internal L3 helpers: refine a bracketed elevation-threshold crossing to a
// sub-second time (bisection), and refine a bracketed elevation maximum to its
// peak time (quadratic interpolation). Pure functions, library-private.
//
// Times are represented as microseconds-since-epoch doubles so the refiners
// operate on a plain real axis; the pass-finder converts back to DateTime.
// Working in microseconds keeps sub-second time resolution well within double
// precision for any realistic search window.

import 'dart:math' as math;

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

/// Estimates the location and value of a maximum from three sample points by
/// fitting a parabola through them (quadratic interpolation).
///
/// The three times [t0] < [t1] < [t2] and their values [f0], [f1], [f2] must
/// bracket an interior maximum (typically `f1 >= f0` and `f1 >= f2`). Returns
/// the vertex of the fitted parabola, clamped to `[t0, t2]`.
///
/// Falls back to the middle sample when the points are collinear (a degenerate
/// parabola with no well-defined vertex).
PeakEstimate quadraticPeak({
  required double t0,
  required double t1,
  required double t2,
  required double f0,
  required double f1,
  required double f2,
}) {
  // Vertex of the parabola through (t0,f0),(t1,f1),(t2,f2). Using the standard
  // three-point formula:
  //   t* = t1 - 0.5 * ((t1-t0)^2 (f1-f2) - (t1-t2)^2 (f1-f0))
  //                  / ((t1-t0)   (f1-f2) - (t1-t2)   (f1-f0))
  final d1 = t1 - t0;
  final d2 = t1 - t2;
  final a = d1 * d1 * (f1 - f2) - d2 * d2 * (f1 - f0);
  final b = d1 * (f1 - f2) - d2 * (f1 - f0);

  if (b == 0.0 || !a.isFinite || !b.isFinite) {
    // Degenerate (collinear) - the middle sample is the best estimate.
    return PeakEstimate(t1, f1);
  }

  var tStar = t1 - 0.5 * a / b;
  // Guard against extrapolation outside the bracket.
  tStar = math.max(t0, math.min(t2, tStar));

  // Evaluate the fitted parabola at tStar to estimate the peak value. Build the
  // quadratic in Lagrange form and evaluate it at tStar.
  final value = _lagrange3(tStar, t0, t1, t2, f0, f1, f2);
  return PeakEstimate(tStar, value);
}

/// Maximizes a unimodal function [f] on `[aUs, cUs]` by golden-section search,
/// returning the peak time/value.
///
/// The bracket must contain a single interior maximum (the coarse sampler
/// guarantees this around its peak grid sample). Unlike [quadraticPeak] - which
/// is exact only for a true parabola - this evaluates [f] directly, so it
/// converges to the real maximum of a curved arc (e.g. a high overhead pass
/// where elevation-vs-time is sharply non-parabolic). Iterates until the
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

// Evaluates the quadratic Lagrange interpolant through three points at [t].
double _lagrange3(
  double t,
  double t0,
  double t1,
  double t2,
  double f0,
  double f1,
  double f2,
) {
  final l0 = ((t - t1) * (t - t2)) / ((t0 - t1) * (t0 - t2));
  final l1 = ((t - t0) * (t - t2)) / ((t1 - t0) * (t1 - t2));
  final l2 = ((t - t0) * (t - t1)) / ((t2 - t0) * (t2 - t1));
  return f0 * l0 + f1 * l1 + f2 * l2;
}
