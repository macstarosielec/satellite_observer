import 'package:meta/meta.dart';
import 'package:satellite_observer/src/domain/look_angle.dart';

/// The kind of a [PassEvent] within a satellite [Pass].
///
/// A pass is bracketed by exactly one [rise] and one [set], with one
/// [culmination] (the highest-elevation instant) in between.
enum PassEventKind {
  /// The satellite crosses the minimum-elevation horizon on the way up.
  rise,

  /// The satellite reaches its maximum elevation during the pass.
  culmination,

  /// The satellite crosses the minimum-elevation horizon on the way down.
  set,
}

/// A single instant of interest within a satellite [Pass].
///
/// Carries the event [kind], the UTC instant [utc] it occurs at, and the
/// topocentric [lookAngle] (azimuth/elevation/range/range-rate) at that
/// instant. All angles inside [lookAngle] are degrees at the public boundary
/// (ADR-13); [utc] is UTC.
@immutable
final class PassEvent {
  /// Creates a [PassEvent] of [kind] at [utc] with the given [lookAngle].
  const PassEvent({
    required this.kind,
    required this.utc,
    required this.lookAngle,
  });

  /// Which point of the pass this event marks (rise, culmination, or set).
  final PassEventKind kind;

  /// The UTC instant this event occurs at.
  ///
  /// Expected to be UTC (ADR-13); matches the [lookAngle]'s `utc`.
  final DateTime utc;

  /// The topocentric look-angle (az/el/range/range-rate) at this event.
  final LookAngle lookAngle;

  @override
  bool operator ==(Object other) =>
      other is PassEvent &&
      kind == other.kind &&
      utc.isAtSameMomentAs(other.utc) &&
      lookAngle == other.lookAngle;

  @override
  int get hashCode => Object.hash(
        kind,
        utc.microsecondsSinceEpoch,
        lookAngle,
      );

  @override
  String toString() =>
      'PassEvent(kind: $kind, utc: $utc, lookAngle: $lookAngle)';
}

/// A single satellite pass over an observer: a rise/culmination/set triple.
///
/// A pass is the interval during which the satellite stays at or above the
/// observer's minimum elevation (ADR-8). The three events are ordered in time:
/// `rise.utc <= culmination.utc <= set.utc`. Callers obtain a [Pass] only via
/// the pass-finder (`SatelliteObserver.passes`), which constructs events in
/// this order; the const constructor does not re-assert it at runtime.
///
/// See `SatelliteObserver.passes` for how passes are found and the boundary
/// policy for partial passes at the search-window edges.
@immutable
final class Pass {
  /// Creates a [Pass] from its [rise], [culmination], and [set] events.
  const Pass({
    required this.rise,
    required this.culmination,
    required this.set,
  });

  /// The rise event: the satellite crossing the horizon on the way up.
  final PassEvent rise;

  /// The culmination event: the satellite at its maximum elevation.
  final PassEvent culmination;

  /// The set event: the satellite crossing the horizon on the way down.
  final PassEvent set;

  /// How long the satellite is above the minimum elevation: `set - rise`.
  Duration get duration => set.utc.difference(rise.utc);

  /// The peak elevation of the pass, in degrees.
  ///
  /// Equal to `culmination.lookAngle.elevationDeg`. The rise/set azimuths are
  /// available via `rise.lookAngle.azimuthDeg` / `set.lookAngle.azimuthDeg`.
  double get peakElevationDeg => culmination.lookAngle.elevationDeg;

  @override
  bool operator ==(Object other) =>
      other is Pass &&
      rise == other.rise &&
      culmination == other.culmination &&
      set == other.set;

  @override
  int get hashCode => Object.hash(rise, culmination, set);

  @override
  String toString() =>
      'Pass(rise: $rise, culmination: $culmination, set: $set)';
}
