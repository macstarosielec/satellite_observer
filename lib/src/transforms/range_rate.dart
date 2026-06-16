// Line-of-sight range-rate from relative velocity (library-private).

import 'package:satellite_observer/src/domain/geo/observer.dart';
import 'package:satellite_observer/src/domain/geo/vector3.dart';
import 'package:satellite_observer/src/transforms/ecef_to_topocentric.dart';

/// Computes the line-of-sight range rate, in kilometres per second.
///
/// The range rate is the relative velocity projected onto the line-of-sight
/// unit vector (FR-7): positive when the satellite is receding from the
/// observer. Both the relative position and the relative velocity are first
/// expressed in the observer's SEZ frame so the projection is frame-consistent.
///
/// * [sezRelative] - observer->satellite relative position in SEZ (km), as
///   produced by [ecefToTopocentric].
/// * [satEcefVelocityKmS] - satellite ECEF velocity (km/s). The observer is
///   fixed in ECEF, so the relative velocity equals the satellite velocity.
/// * [observer] - the observer, used to rotate the velocity into SEZ.
double rangeRate(
  Vector3 sezRelative,
  Vector3 satEcefVelocityKmS,
  Observer observer,
) {
  // Observer is stationary in ECEF, so relative velocity == satellite velocity.
  final sezVelocity = ecefToSez(satEcefVelocityKmS, observer);

  final range = sezRelative.magnitude;
  // Degenerate geometry (zero range) is handled by the caller, which throws a
  // GeometryException before reaching here; guard defensively anyway.
  if (range == 0) {
    return 0;
  }
  // Line-of-sight unit vector dotted with the relative velocity.
  return (sezRelative.x * sezVelocity.x +
          sezRelative.y * sezVelocity.y +
          sezRelative.z * sezVelocity.z) /
      range;
}
