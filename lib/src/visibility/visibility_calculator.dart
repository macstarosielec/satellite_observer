// L4: darkness AND sunlit -> visible sub-intervals (library-private).
//
// For a given Pass (or window), sample at a fine step and find the contiguous
// sub-intervals where the observer is in darkness (Sun topocentric altitude
// below the twilight threshold) AND the satellite is sunlit (ADR-6). Each such
// sub-interval becomes a VisibleInterval; refined edges and the peak look-angle
// within the interval are recorded. The pass-level verdict is a PassVisibility.

import 'package:satellite_observer/src/domain/eci_state.dart';
import 'package:satellite_observer/src/domain/geo/angles.dart';
import 'package:satellite_observer/src/domain/geo/observer.dart';
import 'package:satellite_observer/src/domain/geo/vector3.dart';
import 'package:satellite_observer/src/domain/pass.dart';
import 'package:satellite_observer/src/domain/visibility.dart';
import 'package:satellite_observer/src/propagation/propagation_engine.dart';
import 'package:satellite_observer/src/solar/eclipse.dart';
import 'package:satellite_observer/src/solar/sun_position.dart';
import 'package:satellite_observer/src/transforms/ecef_to_topocentric.dart';
import 'package:satellite_observer/src/transforms/eci_to_ecef.dart';
import 'package:satellite_observer/src/transforms/geodetic.dart';
import 'package:satellite_observer/src/transforms/topocentric.dart' as topo;

/// Returns whether the observer is in darkness at [utc]: the Sun's topocentric
/// altitude is strictly below [sunAltitudeBelowDeg] (FR-12).
///
/// The Sun's geocentric position comes from the analytic Meeus model
/// ([sunPositionEci], ADR-2); its topocentric altitude is computed with the
/// same ECI->ECEF->SEZ machinery the satellite look-angle uses (reusing the P2
/// transforms - the Sun is treated as a very distant "satellite").
bool isObserverInDarknessAt(
  DateTime utc,
  Observer observer, {
  required double sunAltitudeBelowDeg,
}) {
  return sunTopocentricAltitudeDeg(utc, observer) < sunAltitudeBelowDeg;
}

/// Returns the Sun's geometric topocentric altitude at [utc] for [observer], in
/// degrees (no atmospheric refraction; ADR-6 / NG5).
///
/// The Sun's geocentric ECI position (Meeus, ADR-2) is rotated into ECEF by
/// GMST, the observer's ECEF position is subtracted, and the result is taken
/// into the local SEZ frame to read the elevation. Reuses the P2 transforms
/// directly (no duplicated math).
double sunTopocentricAltitudeDeg(DateTime utc, Observer observer) {
  final sun = sunPositionEci(utc);
  // The Sun as a zero-velocity ECI state so we can reuse temeToEcef directly.
  final sunState = EciState(
    position: sun.positionKm,
    velocity: const Vector3(0, 0, 0),
    utc: utc,
  );
  final sunEcef = temeToEcef(sunState);
  final observerEcef = observerToEcef(observer);
  final result = ecefToTopocentric(sunEcef.position, observer, observerEcef);
  return degrees(result.elevationRad);
}

/// Returns whether the satellite is sunlit at [utc] (ADR-6, FR-13).
///
/// Propagates the satellite to [utc] (TEME), takes the Meeus Sun direction at
/// the same instant, and runs the geometric conical-umbra test. The Sun
/// direction and the satellite position are treated as being in the same
/// inertial frame (see [sunPositionEci] on the TEME-vs-equinox-of-date
/// simplification).
bool isSatelliteSunlitAt(DateTime utc, PropagationEngine engine) {
  final state = engine.propagate(utc);
  final sun = sunPositionEci(utc);
  return isSunlit(
    state.position,
    sun.direction,
    sunDistanceKm: sun.positionKm.magnitude,
  );
}

/// Computes the [PassVisibility] for [pass] (FR-14).
///
/// Samples the pass interval `[rise, set]` on a fixed [sampleStep] and finds
/// the contiguous runs where the observer is in darkness (Sun altitude below
/// [sunAltitudeBelowDeg]) AND the satellite is sunlit. Each run becomes a
/// [VisibleInterval] whose start/end are refined to the transition by bisection
/// (bisected to within 100 ms via [edgeRefineToleranceUs]), and whose
/// [VisibleInterval.peakLookAngle] is the highest-elevation sample inside it.
///
/// ## Sampling and edge policy
///
/// The visibility condition (`dark AND sunlit`) is a boolean that changes at
/// most a handful of times across one short LEO pass (typically once or twice:
/// the satellite entering/leaving the umbra, and the sky crossing the twilight
/// threshold over the minutes-long pass). A [sampleStep] of a few seconds
/// resolves those transitions; the default of `2` s is comfortably finer than
/// the umbra-crossing rate of an ISS-class pass. Each detected on->off or
/// off->on transition is then bisected to the sub-second instant so interval
/// edges are not quantised to the coarse grid.
///
/// Endpoints: the pass endpoints (`rise`, `set`) themselves bound the search;
/// if the satellite is already visible at `rise` (or still visible at `set`)
/// the interval simply starts at `rise` (ends at `set`). Intervals are
/// half-clamped to the pass, never extended outside it.
PassVisibility computePassVisibility(
  Pass pass, {
  required Observer observer,
  required PropagationEngine engine,
  required double sunAltitudeBelowDeg,
  Duration sampleStep = const Duration(seconds: 2),
  double edgeRefineToleranceUs = 1.0e5, // 100 ms (0.1 s)
}) {
  bool visibleAt(DateTime utc) {
    if (!isObserverInDarknessAt(
      utc,
      observer,
      sunAltitudeBelowDeg: sunAltitudeBelowDeg,
    )) {
      return false;
    }
    return isSatelliteSunlitAt(utc, engine);
  }

  // Signed "visible margin" as a function of time (microseconds), used only for
  // bisecting a transition: +1 when visible, -1 when not. The sampler already
  // brackets a sign change before this is called.
  double visibleSign(double timeUs) {
    final utc = DateTime.fromMicrosecondsSinceEpoch(
      timeUs.round(),
      isUtc: true,
    );
    return visibleAt(utc) ? 1.0 : -1.0;
  }

  // Refine an on/off transition bracketed by [loUs, hiUs] (differing booleans)
  // to the boundary, returning the boundary time in microseconds.
  double refineEdge(double loUs, double hiUs) {
    var lo = loUs;
    var hi = hiUs;
    final fLo = visibleSign(lo);
    while (hi - lo > edgeRefineToleranceUs) {
      final mid = lo + (hi - lo) / 2.0;
      if (visibleSign(mid) == fLo) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo + (hi - lo) / 2.0;
  }

  final startUs = pass.rise.utc.microsecondsSinceEpoch;
  final endUs = pass.set.utc.microsecondsSinceEpoch;
  final stepUs = sampleStep.inMicroseconds;

  // Sample the pass interval inclusive of both endpoints.
  final sampleTimesUs = <int>[];
  for (var t = startUs; t < endUs; t += stepUs) {
    sampleTimesUs.add(t);
  }
  sampleTimesUs.add(endUs);

  final intervals = <VisibleInterval>[];

  // Walk the samples, opening an interval on a false->true edge and closing it
  // on a true->false edge, refining each edge to the sub-second boundary.
  var prevVisible = false;
  double? openStartUs;
  var prevUs = startUs.toDouble();

  for (var i = 0; i < sampleTimesUs.length; i++) {
    final tUs = sampleTimesUs[i].toDouble();
    final utc = DateTime.fromMicrosecondsSinceEpoch(
      sampleTimesUs[i],
      isUtc: true,
    );
    final vis = visibleAt(utc);

    if (i == 0) {
      prevVisible = vis;
      prevUs = tUs;
      if (vis) {
        openStartUs = tUs; // visible from the very start of the pass
      }
      continue;
    }

    if (vis && !prevVisible) {
      // false -> true: refine the rising edge in (prevUs, tUs).
      openStartUs = refineEdge(prevUs, tUs);
    } else if (!vis && prevVisible) {
      // true -> false: refine the falling edge in (prevUs, tUs) and close.
      final closeUs = refineEdge(prevUs, tUs);
      intervals.add(
        _buildInterval(
          startUs: openStartUs!,
          endUs: closeUs,
          observer: observer,
          engine: engine,
        ),
      );
      openStartUs = null;
    }

    prevVisible = vis;
    prevUs = tUs;
  }

  // An interval still open at the pass end closes at the set instant.
  if (openStartUs != null) {
    intervals.add(
      _buildInterval(
        startUs: openStartUs,
        endUs: endUs.toDouble(),
        observer: observer,
        engine: engine,
      ),
    );
  }

  return PassVisibility(
    pass: pass,
    isVisible: intervals.isNotEmpty,
    // Wrap so callers cannot mutate the result (PassVisibility is @immutable).
    // Built at runtime, so this non-const construction is fine.
    visibleIntervals: List.unmodifiable(intervals),
  );
}

/// Builds a [VisibleInterval] for `[startUs, endUs]`, scanning inside it for
/// the highest-elevation look-angle (the peak).
VisibleInterval _buildInterval({
  required double startUs,
  required double endUs,
  required Observer observer,
  required PropagationEngine engine,
}) {
  final startUtc = DateTime.fromMicrosecondsSinceEpoch(
    startUs.round(),
    isUtc: true,
  );
  final endUtc = DateTime.fromMicrosecondsSinceEpoch(
    endUs.round(),
    isUtc: true,
  );

  // Scan the interval on a fine grid for the highest-elevation look-angle.
  // A short pass is at most a few minutes; a 1 s scan grid is cheap and finds
  // the peak to within a degree of arc of the true maximum, which is all the
  // "look here" pointer needs.
  const scanStepUs = 1000000; // 1 s
  final startRounded = startUs.round();
  final endRounded = endUs.round();
  var best = topo.topocentricLookAngle(
    engine.propagate(
      DateTime.fromMicrosecondsSinceEpoch(startRounded, isUtc: true),
    ),
    observer,
  );
  var tUs = startRounded + scanStepUs;
  while (tUs <= endRounded) {
    final utc = DateTime.fromMicrosecondsSinceEpoch(tUs, isUtc: true);
    final la = topo.topocentricLookAngle(engine.propagate(utc), observer);
    if (la.elevationDeg > best.elevationDeg) {
      best = la;
    }
    if (tUs == endRounded) break;
    tUs += scanStepUs;
    if (tUs > endRounded) tUs = endRounded;
  }

  return VisibleInterval(
    startUtc: startUtc,
    endUtc: endUtc,
    peakLookAngle: best,
  );
}
