import 'package:satellite_observer/src/domain/eci_state.dart';
import 'package:satellite_observer/src/domain/geo/observer.dart';
import 'package:satellite_observer/src/domain/gp_elements.dart';
import 'package:satellite_observer/src/domain/look_angle.dart';
import 'package:satellite_observer/src/domain/pass.dart';
import 'package:satellite_observer/src/domain/sub_point.dart';
import 'package:satellite_observer/src/domain/twilight_phase.dart';
import 'package:satellite_observer/src/domain/visibility.dart';
import 'package:satellite_observer/src/passes/pass_finder.dart';
import 'package:satellite_observer/src/propagation/propagation_engine.dart';
import 'package:satellite_observer/src/propagation/sgp4/sgp4_engine.dart';
import 'package:satellite_observer/src/transforms/topocentric.dart' as topo;
import 'package:satellite_observer/src/visibility/visibility_calculator.dart'
    as vis;

/// Named minimum-elevation presets for [SatelliteObserver.passes] (ADR-8).
///
/// These are a small, self-documenting convenience over passing a raw
/// `minElevationDeg`: read the use-site intent rather than a bare number.
///
/// * [obstructed] - `10` deg, the default. A realistic value for a typical
///   site with trees/buildings near the horizon, so out-of-the-box passes are
///   plausibly observable rather than horizon-hugging.
/// * [openSky] - `0` deg, the true geometric horizon, for an unobstructed site.
enum HorizonMask {
  /// A typical obstructed site: minimum elevation `10` deg (the default).
  obstructed(10),

  /// An unobstructed open-sky site: minimum elevation `0` deg (true horizon).
  openSky(0);

  const HorizonMask(this.minElevationDeg);

  /// The minimum elevation, in degrees, this mask corresponds to.
  final double minElevationDeg;
}

/// The public entry point: propagate, look-angles, sub-points, and passes for
/// one satellite as seen from one observer.
///
/// Construct it from generic [GpElements] (FR-1) and an [Observer]; the default
/// propagation engine is an [Sgp4Engine] over those elements, swappable via the
/// optional `engine` argument (ADR-1). All angles are degrees and all times are
/// UTC at this boundary (ADR-13).
///
/// ## Reuse: construct once, call across ticks
///
/// Construction runs the SGP4 initialisation ([Sgp4Engine] executes `sgp4init`
/// exactly once in its constructor), which costs roughly as much as a single
/// propagation. Construct one [SatelliteObserver] per satellite up front and
/// reuse it for every tick - do **not** rebuild a fresh observer (or
/// [Sgp4Engine]) per frame in a live tracker, which would re-pay that setup on
/// every tick on top of the propagation, and far more inside a [passes] /
/// [visiblePasses] search (which propagates many times internally). When the
/// same initialised propagator must serve multiple observers (for example one
/// satellite seen from several sites), build the [Sgp4Engine] once and pass it
/// via the `engine` argument to each [SatelliteObserver] - that single,
/// cache-friendly propagator then drives them all without re-running
/// `sgp4init`.
///
/// ## Minimum elevation default
///
/// [passes] and [nextPass] default `minElevationDeg` to **`10` deg** (ADR-8),
/// not the geometric horizon. `10` deg is a realistic obstructed-site value, so
/// the default result is plausibly observable rather than full of
/// horizon-hugging passes hidden behind trees and buildings. Pass
/// `minElevationDeg: 0` (or `HorizonMask.openSky.minElevationDeg`) for the true
/// geometric horizon, or a higher value for a hilly site. Sub-threshold passes
/// are intentionally excluded; this default is documented here so a caller is
/// never surprised by "missing" low passes.
///
/// ## Visibility (L4)
///
/// A pass is *visible* only where the observer is in darkness (the Sun is below
/// a twilight threshold) AND the satellite is sunlit (not in Earth's shadow).
/// [visiblePasses] combines both into [PassVisibility] verdicts;
/// [isObserverInDarkness] and [isSatelliteSunlit] expose the two halves. The
/// darkness threshold defaults to [TwilightPhase.civil] (`-6` deg, ADR-7); pass
/// a raw `sunAltitudeBelowDeg` to override it. The Sun model is analytic Meeus
/// (~arc-minute, no ephemeris/network, ADR-2) and the eclipse test is a
/// geometric conical umbra ignoring atmospheric refraction (ADR-6) - spotter
/// grade, not survey grade (NFR-2).
final class SatelliteObserver {
  /// Creates a [SatelliteObserver] for [elements] seen from [observer].
  ///
  /// If [engine] is omitted, an [Sgp4Engine] is built from [elements]. When
  /// [engine] is supplied, [elements] is ignored and the supplied engine drives
  /// all propagation; the engine owns the epoch ([epoch] delegates to
  /// `engine.epoch`).
  SatelliteObserver({
    required GpElements elements,
    required Observer observer,
    PropagationEngine? engine,
  })  : _observer = observer,
        _engine = engine ?? Sgp4Engine(elements);

  final Observer _observer;
  final PropagationEngine _engine;

  /// The epoch of the underlying elements, as a UTC instant (FR-5).
  DateTime get epoch => _engine.epoch;

  /// Propagates the orbit to [utc] and returns the TEME-frame state (FR-3).
  EciState propagate(DateTime utc) => _engine.propagate(utc);

  /// Propagates the orbit across `[from, to]` on a fixed [step], inclusive of
  /// both endpoints (FR-4).
  ///
  /// Lazily yields one [EciState] per sample. [from] must precede [to] and
  /// [step] must be positive, else an [ArgumentError] is thrown (eagerly, when
  /// the iterable is created).
  Iterable<EciState> propagateSeries({
    required DateTime from,
    required DateTime to,
    required Duration step,
  }) {
    _validateWindow(from: from, to: to);
    if (step <= Duration.zero) {
      throw ArgumentError.value(step, 'step', 'must be positive');
    }
    return _series(from: from.toUtc(), to: to.toUtc(), step: step);
  }

  Iterable<EciState> _series({
    required DateTime from,
    required DateTime to,
    required Duration step,
  }) sync* {
    final toUs = to.microsecondsSinceEpoch;
    final stepUs = step.inMicroseconds;
    var t = from.microsecondsSinceEpoch;
    while (t < toUs) {
      yield _engine.propagate(
        DateTime.fromMicrosecondsSinceEpoch(t, isUtc: true),
      );
      t += stepUs;
    }
    // Always include the exact `to` endpoint.
    yield _engine.propagate(to);
  }

  /// The topocentric [LookAngle] from the observer to the satellite at [utc]
  /// (FR-6/7).
  LookAngle lookAngleAt(DateTime utc) =>
      topo.topocentricLookAngle(_engine.propagate(utc), _observer);

  /// The [SubSatellitePoint] (geodetic point beneath the satellite) at [utc]
  /// (FR-8).
  SubSatellitePoint subPointAt(DateTime utc) =>
      topo.subSatellitePoint(_engine.propagate(utc));

  /// Finds all fully-bracketed passes in `[from, to]` (FR-9/10/11).
  ///
  /// A pass is the interval the satellite spends at or above [minElevationDeg]
  /// (default `10` deg per ADR-8 - see the class docs for the rationale). Each
  /// [Pass] carries refined rise/culmination/set events.
  ///
  /// The search coarse-samples elevation on [sampleStep] (default `30` s,
  /// ADR-5) then refines crossings/peaks to sub-second precision. The default
  /// step is fine enough that no realistic LEO pass is skipped; shorten it for
  /// very fast or grazing passes.
  ///
  /// Boundary policy: only fully-bracketed passes are returned. A pass already
  /// in progress at [from], or still in progress at [to], is omitted because
  /// its rise/set crossing is not observed inside the window; widen the window
  /// to capture it.
  ///
  /// Throws an [ArgumentError] if [from] is not before [to], if
  /// [minElevationDeg] is outside `[0, 90)`, or if [sampleStep] is not
  /// positive.
  List<Pass> passes({
    required DateTime from,
    required DateTime to,
    double minElevationDeg = 10,
    Duration sampleStep = const Duration(seconds: 30),
  }) {
    _validateWindow(from: from, to: to);
    _validateMinElevation(minElevationDeg);
    if (sampleStep <= Duration.zero) {
      throw ArgumentError.value(sampleStep, 'sampleStep', 'must be positive');
    }
    return findPasses(
      lookAngleAt: lookAngleAt,
      from: from,
      to: to,
      minElevationDeg: minElevationDeg,
      sampleStep: sampleStep,
    );
  }

  /// The first pass at or after [after] within [within], or `null` if none.
  ///
  /// Convenience sugar over [passes]: it searches `[after, after + within]`
  /// and returns the earliest fully-bracketed pass. No new computation - same
  /// math, same defaults ([minElevationDeg] = `10`, ADR-8). For the boundary
  /// policy on in-progress passes see [passes].
  ///
  /// Throws an [ArgumentError] if [within] is not positive or [minElevationDeg]
  /// is outside `[0, 90)`.
  Pass? nextPass({
    required DateTime after,
    Duration within = const Duration(hours: 48),
    double minElevationDeg = 10,
  }) {
    if (within <= Duration.zero) {
      throw ArgumentError.value(within, 'within', 'must be positive');
    }
    _validateMinElevation(minElevationDeg);
    final found = passes(
      from: after,
      to: after.toUtc().add(within),
      minElevationDeg: minElevationDeg,
    );
    return found.isEmpty ? null : found.first;
  }

  // L4 - the headline (FR-12/13/14).

  /// Finds passes in `[from, to]` and marks the naked-eye-visible sub-intervals
  /// of each (FR-14) - the headline capability.
  ///
  /// First runs [passes] (same geometry, same [minElevationDeg] default of `10`
  /// deg, ADR-8), then for each pass computes where the observer is in darkness
  /// AND the satellite is sunlit, yielding a [PassVisibility] per pass (a pass
  /// with no visible sub-interval has `isVisible == false` and an empty
  /// interval list, but is still returned so callers see the full pass set).
  ///
  /// The darkness threshold is [twilight] (default [TwilightPhase.civil], `-6`
  /// deg). If [sunAltitudeBelowDeg] is supplied it overrides [twilight] with a
  /// raw Sun-altitude threshold in degrees (ADR-7).
  ///
  /// Each pass is sampled at 2 s intervals to detect dark-and-sunlit
  /// transitions; each detected edge is then bisected to ~100 ms.
  ///
  /// Throws an [ArgumentError] if [from] is not before [to], or if
  /// [minElevationDeg] is outside `[0, 90)` (delegated to [passes]).
  List<PassVisibility> visiblePasses({
    required DateTime from,
    required DateTime to,
    double minElevationDeg = 10,
    TwilightPhase twilight = TwilightPhase.civil,
    double? sunAltitudeBelowDeg,
  }) {
    final threshold = _darknessThreshold(twilight, sunAltitudeBelowDeg);
    final found = passes(
      from: from,
      to: to,
      minElevationDeg: minElevationDeg,
    );
    return found
        .map(
          (pass) => vis.computePassVisibility(
            pass,
            observer: _observer,
            engine: _engine,
            sunAltitudeBelowDeg: threshold,
          ),
        )
        .toList(growable: false);
  }

  /// Whether the observer is in darkness at [utc] (FR-12).
  ///
  /// The observer is in darkness when the Sun's geometric topocentric altitude
  /// (Meeus model, ADR-2; no atmospheric refraction) is below the threshold:
  /// [twilight]`.sunAltitudeDegrees` (default [TwilightPhase.civil], `-6` deg),
  /// or the raw [sunAltitudeBelowDeg] in degrees if supplied (which overrides
  /// [twilight], ADR-7).
  bool isObserverInDarkness(
    DateTime utc, {
    TwilightPhase twilight = TwilightPhase.civil,
    double? sunAltitudeBelowDeg,
  }) {
    final threshold = _darknessThreshold(twilight, sunAltitudeBelowDeg);
    return vis.isObserverInDarknessAt(
      utc.toUtc(),
      _observer,
      sunAltitudeBelowDeg: threshold,
    );
  }

  /// Whether the satellite is sunlit (not in Earth's shadow) at [utc] (FR-13).
  ///
  /// Propagates to [utc] and runs the geometric conical-umbra test against the
  /// Meeus Sun direction (ADR-6). `false` means the satellite is in Earth's
  /// umbra (eclipsed) and so cannot reflect sunlight to the ground.
  bool isSatelliteSunlit(DateTime utc) =>
      vis.isSatelliteSunlitAt(utc.toUtc(), _engine);

  /// The first naked-eye-visible pass at or after [after] within [within], or
  /// `null` if none.
  ///
  /// Convenience sugar over [visiblePasses]: it searches `[after, after +
  /// within]` and returns the earliest [PassVisibility] whose `isVisible` is
  /// `true`. No new computation - same Sun/eclipse model and the same
  /// [minElevationDeg] default (`10`, ADR-8) and [twilight] default
  /// ([TwilightPhase.civil]).
  ///
  /// Throws an [ArgumentError] if [within] is not positive or [minElevationDeg]
  /// is outside `[0, 90)`.
  PassVisibility? nextVisiblePass({
    required DateTime after,
    Duration within = const Duration(hours: 48),
    double minElevationDeg = 10,
    TwilightPhase twilight = TwilightPhase.civil,
  }) {
    if (within <= Duration.zero) {
      throw ArgumentError.value(within, 'within', 'must be positive');
    }
    _validateMinElevation(minElevationDeg);
    final all = visiblePasses(
      from: after,
      to: after.toUtc().add(within),
      minElevationDeg: minElevationDeg,
      twilight: twilight,
    );
    for (final pv in all) {
      if (pv.isVisible) return pv;
    }
    return null;
  }

  /// Resolves the darkness threshold (deg): the raw override when supplied,
  /// otherwise the [twilight] phase's `sunAltitudeDegrees`.
  double _darknessThreshold(
    TwilightPhase twilight,
    double? sunAltitudeBelowDeg,
  ) =>
      sunAltitudeBelowDeg ?? twilight.sunAltitudeDegrees;

  void _validateWindow({required DateTime from, required DateTime to}) {
    if (!from.toUtc().isBefore(to.toUtc())) {
      throw ArgumentError('`from` ($from) must be before `to` ($to)');
    }
  }

  void _validateMinElevation(double minElevationDeg) {
    if (!(minElevationDeg >= 0.0 && minElevationDeg < 90.0)) {
      throw ArgumentError.value(
        minElevationDeg,
        'minElevationDeg',
        'must be in [0, 90)',
      );
    }
  }
}
