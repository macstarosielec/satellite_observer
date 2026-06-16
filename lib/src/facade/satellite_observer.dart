import 'package:satellite_observer/src/domain/eci_state.dart';
import 'package:satellite_observer/src/domain/geo/observer.dart';
import 'package:satellite_observer/src/domain/gp_elements.dart';
import 'package:satellite_observer/src/domain/look_angle.dart';
import 'package:satellite_observer/src/domain/pass.dart';
import 'package:satellite_observer/src/domain/sub_point.dart';
import 'package:satellite_observer/src/passes/pass_finder.dart';
import 'package:satellite_observer/src/propagation/propagation_engine.dart';
import 'package:satellite_observer/src/propagation/sgp4/sgp4_engine.dart';
import 'package:satellite_observer/src/transforms/topocentric.dart' as topo;

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
/// ## Surface scope (phasing)
///
/// The L4 visibility methods (`visiblePasses`, `isObserverInDarkness`,
/// `isSatelliteSunlit`, `nextVisiblePass`) are added in a later phase (P4), so
/// the current surface is geometry-only and not yet the complete API.
final class SatelliteObserver {
  /// Creates a [SatelliteObserver] for [elements] seen from [observer].
  ///
  /// If [engine] is omitted, an [Sgp4Engine] is created from [elements]. When
  /// [engine] is supplied, it drives propagation and [elements] is used only to
  /// build the default engine; the engine owns the epoch ([epoch] delegates to
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
