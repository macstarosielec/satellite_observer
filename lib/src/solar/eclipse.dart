// Geometric conical-umbra sunlit/eclipsed test (library-private, ADR-6).
//
// A satellite is eclipsed when it lies in Earth's umbra (full shadow): it is on
// the anti-solar side of Earth AND its perpendicular distance from the
// Earth-Sun axis is less than the umbra cone's radius at that point. The cone
// narrows with distance behind Earth because the Sun is an extended source.
// Atmospheric refraction of sunlight is ignored (documented, NFR-2 / NG5).

import 'dart:math' as math;

import 'package:satellite_observer/src/domain/geo/vector3.dart';

/// Mean equatorial radius of the Earth, in km (ADR-6: mean equatorial radius).
///
/// This matches the WGS-84 semi-major axis used elsewhere in the library.
const double earthMeanEquatorialRadiusKm = 6378.137;

/// Radius of the Sun, in km (IAU nominal solar radius).
const double sunRadiusKm = 696000;

/// Returns whether a satellite at geocentric ECI position [satEciKm] (km) is
/// sunlit, given the unit Earth->Sun [sunDirection] (ADR-6, FR-13).
///
/// Geometry (conical umbra):
///
/// 1. Project the satellite onto the Earth-Sun axis. If the projection is on
///    the *sunward* side (the component along [sunDirection] is positive), the
///    satellite cannot be in Earth's shadow, so it is sunlit.
/// 2. Otherwise the satellite is behind Earth. Let `d` be its perpendicular
///    distance from the axis and `x` its distance behind Earth's centre along
///    the anti-solar direction. The umbra is a cone whose apex sits behind
///    Earth at distance `x_apex = R_earth / sin(alpha)` from Earth's centre,
///    where `sin(alpha) = (R_sun - R_earth) / sunDistance` is the umbra cone's
///    half-angle. The umbra radius at distance `x` is
///    `r_umbra(x) = (x_apex - x) * tan(alpha)`, shrinking to zero at the apex.
///    The satellite is eclipsed (in umbra) when `d < r_umbra(x)` and
///    `x < x_apex` (i.e. before the cone closes).
///
/// The Sun's finite distance enters through the half-angle. Because the Sun is
/// vastly larger than Earth, `alpha` is small and the umbra extends far beyond
/// any LEO/MEO altitude, but the conical (not cylindrical) form is used so the
/// test is correct out to GEO and beyond.
///
/// [sunDistanceKm] is the Earth-Sun distance for the instant (from the Meeus
/// model); it sets the umbra cone's half-angle. [sunDirection] must be a unit
/// vector; the function normalises defensively.
bool isSunlit(
  Vector3 satEciKm,
  Vector3 sunDirection, {
  double sunDistanceKm = 149597870.7,
}) {
  // Normalise the Sun direction defensively (the Meeus direction is already
  // unit-length to rounding, but be robust).
  final sMag = sunDirection.magnitude;
  if (sMag == 0 || !sMag.isFinite) {
    // No usable Sun direction: treat as sunlit (cannot prove eclipse).
    return true;
  }
  final sx = sunDirection.x / sMag;
  final sy = sunDirection.y / sMag;
  final sz = sunDirection.z / sMag;

  // Component of the satellite position along the Sun direction. Positive means
  // the satellite is on the sunward side of Earth's centre.
  final along = satEciKm.x * sx + satEciKm.y * sy + satEciKm.z * sz;
  if (along >= 0) {
    // Sunward hemisphere: never in Earth's shadow.
    return true;
  }

  // Distance behind Earth along the anti-solar axis (positive).
  final x = -along;

  // Perpendicular (radial) distance from the Earth-Sun axis.
  final perpSq = satEciKm.x * satEciKm.x +
      satEciKm.y * satEciKm.y +
      satEciKm.z * satEciKm.z -
      along * along;
  final perp = perpSq <= 0 ? 0.0 : math.sqrt(perpSq);

  // Umbra cone half-angle: sin(alpha) = (R_sun - R_earth) / sunDistance.
  final sinAlpha = (sunRadiusKm - earthMeanEquatorialRadiusKm) / sunDistanceKm;
  final alpha = math.asin(sinAlpha);
  final tanAlpha = math.tan(alpha);

  // Distance from Earth's centre to the umbra cone apex (behind Earth).
  final xApex = earthMeanEquatorialRadiusKm / sinAlpha;

  if (x >= xApex) {
    // Beyond the umbra apex: the full shadow has closed, so sunlit.
    return true;
  }

  // Umbra radius at this distance behind Earth.
  final umbraRadius = (xApex - x) * tanAlpha;

  // Eclipsed (in umbra) when within the cone's radius; otherwise sunlit.
  return perp >= umbraRadius;
}
