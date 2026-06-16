// ECEF -> topocentric SEZ -> azimuth/elevation/range (library-private).

import 'dart:math' as math;

import 'package:satellite_observer/src/domain/failures.dart';
import 'package:satellite_observer/src/domain/geo/angles.dart';
import 'package:satellite_observer/src/domain/geo/observer.dart';
import 'package:satellite_observer/src/domain/geo/vector3.dart';

/// A topocentric look in the local South-East-Zenith (SEZ) frame.
///
/// Internal carrier between the ECEF stage and the public look-angle:
/// azimuth and elevation are in radians, range in kilometres, and the SEZ
/// relative vector is retained so the range-rate stage can project the
/// relative velocity onto the line of sight without recomputing the rotation.
class TopocentricSez {
  /// Creates a [TopocentricSez] result.
  const TopocentricSez({
    required this.azimuthRad,
    required this.elevationRad,
    required this.rangeKm,
    required this.sezRelative,
  });

  /// Azimuth in radians, `0` = north, clockwise, in `[0, 2*pi)`.
  final double azimuthRad;

  /// Elevation above the horizon in radians; negative means below.
  final double elevationRad;

  /// Slant range in kilometres.
  final double rangeKm;

  /// The observer->satellite relative vector expressed in the SEZ frame (km):
  /// `(south, east, zenith)`.
  final Vector3 sezRelative;
}

/// Rotates an ECEF [relativeVector] (satellite ECEF minus observer ECEF) into
/// the observer's local SEZ frame.
///
/// The SEZ axes at the observer's geodetic latitude `lat` and longitude `lon`,
/// applied to the ECEF relative components `(dx, dy, dz)`:
///
/// ```text
/// south  =  sinLat*cosLon*dx + sinLat*sinLon*dy - cosLat*dz
/// east   = -sinLon*dx        + cosLon*dy
/// zenith =  cosLat*cosLon*dx + cosLat*sinLon*dy + sinLat*dz
/// ```
Vector3 ecefToSez(Vector3 relativeVector, Observer observer) {
  final lat = radians(observer.latitudeDeg);
  final lon = radians(observer.longitudeDeg);
  final sinLat = math.sin(lat);
  final cosLat = math.cos(lat);
  final sinLon = math.sin(lon);
  final cosLon = math.cos(lon);

  final dx = relativeVector.x;
  final dy = relativeVector.y;
  final dz = relativeVector.z;

  final south = sinLat * cosLon * dx + sinLat * sinLon * dy - cosLat * dz;
  final east = -sinLon * dx + cosLon * dy;
  final zenith = cosLat * cosLon * dx + cosLat * sinLon * dy + sinLat * dz;

  return Vector3(south, east, zenith);
}

/// Computes azimuth, elevation and slant range from the satellite ECEF
/// position [satEcefKm], the observer geodetic [observer] and its ECEF
/// position [observerEcefKm].
///
/// Azimuth is `atan2(east, -south)` normalised to `[0, 2*pi)` (`0` = north,
/// clockwise); elevation is `asin(zenith / range)`. The full SEZ relative
/// vector is returned for the range-rate stage.
///
/// Throws a [GeometryException] when the slant range is zero or non-finite
/// (e.g. the satellite coincides with the observer). The guard runs before the
/// `asin`/`atan2` so no NaN-bearing result is ever constructed.
TopocentricSez ecefToTopocentric(
  Vector3 satEcefKm,
  Observer observer,
  Vector3 observerEcefKm,
) {
  final relative = Vector3(
    satEcefKm.x - observerEcefKm.x,
    satEcefKm.y - observerEcefKm.y,
    satEcefKm.z - observerEcefKm.z,
  );
  final sez = ecefToSez(relative, observer);

  final range = sez.magnitude;
  if (range == 0 || !range.isFinite) {
    throw const GeometryException(
      'Degenerate look geometry: zero or non-finite slant range '
      '(satellite coincides with observer)',
    );
  }
  final elevation = math.asin(sez.z / range);
  final azimuth = normalizeTwoPi(math.atan2(sez.y, -sez.x));

  return TopocentricSez(
    azimuthRad: azimuth,
    elevationRad: elevation,
    rangeKm: range,
    sezRelative: sez,
  );
}
