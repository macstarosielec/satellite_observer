// Analytic Meeus low-precision solar position (library-private, ADR-2).
//
// Implements the low-accuracy Sun algorithm from Jean Meeus, "Astronomical
// Algorithms" (2nd ed.), chapter 25 ("Solar Coordinates"). Accuracy is about
// 0.01 deg (arc-minute level) in the Sun's direction - far better than needed
// for a twilight gate on a -6/-12/-18 deg threshold and for the umbra test
// (ADR-2). No ephemeris, no network, no assets: pure dart:math.

import 'dart:math' as math;

import 'package:satellite_observer/src/domain/geo/angles.dart';
import 'package:satellite_observer/src/domain/geo/vector3.dart';
import 'package:satellite_observer/src/domain/time/gmst.dart';

/// The mean distance from Earth to the Sun (one astronomical unit), in km.
const double astronomicalUnitKm = 149597870.7;

/// The geocentric Sun position produced by the analytic Meeus model.
///
/// Carries both the unit [direction] (Earth -> Sun) and the full [positionKm]
/// (geocentric, scaled by the Earth-Sun distance). The frame is discussed on
/// [sunPositionEci]: it is the equator/equinox of date, which the rest of the
/// library treats as interchangeable with the TEME frame the SGP4 engine
/// produces (the sub-arc-minute difference is negligible for a twilight gate
/// and the umbra test, ADR-2).
class SunPosition {
  /// Creates a [SunPosition] from its geocentric [positionKm] and the matching
  /// unit [direction].
  const SunPosition({required this.positionKm, required this.direction});

  /// The geocentric Sun position, in km, in the equator/equinox-of-date frame
  /// (treated as TEME-equivalent; see [sunPositionEci]).
  final Vector3 positionKm;

  /// The unit vector from the Earth's centre toward the Sun, same frame as
  /// [positionKm].
  final Vector3 direction;
}

/// Computes the geocentric Sun position at the UTC instant [utc] using the
/// Meeus low-precision algorithm (ADR-2).
///
/// ## Frame assumption
///
/// The algorithm yields the Sun's apparent right ascension and declination
/// referred to the **mean equator and equinox of date**. The SGP4 engine and
/// the rest of this library work in the **TEME** frame. TEME differs from the
/// equinox-of-date frame only by the equation of the equinoxes (a rotation of
/// at most ~1.1 arc-seconds about the pole) plus the tiny frame-bias/precession
/// already folded into "of date". For a Sun direction this is far below the
/// model's own ~arc-minute accuracy, so the two are treated as the same
/// inertial frame here (ADR-2). This is the same simplification the GMST
/// rotation makes (UT1 ~= UTC, no nutation/polar motion; ADR-4 / NG5).
///
/// The returned position is geocentric (Earth-centred), scaled by the true
/// Earth-Sun distance, so it can be used directly both for the unit direction
/// (umbra test, ADR-6) and - via the observer's local frame - for the Sun's
/// topocentric altitude (the twilight check, ADR-7).
SunPosition sunPositionEci(DateTime utc) {
  // Julian centuries of (approximately) TDT since J2000.0. We reuse the same
  // julianDate(UTC) the rest of the library uses; the UTC-vs-TT difference
  // (~69 s in this era) shifts the Sun's mean longitude by < 0.001 deg, well
  // below the model's accuracy.
  final jd = julianDate(utc);
  final t = (jd - 2451545.0) / 36525.0;

  // Geometric mean longitude of the Sun, referred to the mean equinox of date
  // (Meeus 25.2), in degrees.
  final l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;

  // Mean anomaly of the Sun (Meeus 25.3), in degrees.
  final m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t;
  final mRad = radians(m);

  // Eccentricity of Earth's orbit (Meeus 25.4); dimensionless.
  final e = 0.016708634 - 0.000042037 * t - 0.0000001267 * t * t;

  // Sun's equation of the centre (Meeus, p. 164), in degrees.
  final c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * math.sin(mRad) +
      (0.019993 - 0.000101 * t) * math.sin(2.0 * mRad) +
      0.000289 * math.sin(3.0 * mRad);

  // True longitude and true anomaly of the Sun, in degrees.
  final trueLongitude = l0 + c;
  final trueAnomaly = m + c;

  // Sun's radius vector (distance), in astronomical units (Meeus 25.5).
  final rAu = (1.000001018 * (1.0 - e * e)) /
      (1.0 + e * math.cos(radians(trueAnomaly)));

  // Apparent longitude: correct for nutation and aberration (Meeus, p. 164).
  final omega = 125.04 - 1934.136 * t; // deg
  final apparentLongitude =
      trueLongitude - 0.00569 - 0.00478 * math.sin(radians(omega));
  final lambda = radians(apparentLongitude);

  // Mean obliquity of the ecliptic (Meeus 22.2), in degrees, then the apparent
  // obliquity (corrected by the same nutation term, Meeus p. 165).
  final epsilon0 = 23.0 +
      26.0 / 60.0 +
      21.448 / 3600.0 -
      (46.8150 / 3600.0) * t -
      (0.00059 / 3600.0) * t * t +
      (0.001813 / 3600.0) * t * t * t;
  final epsilon = radians(epsilon0 + 0.00256 * math.cos(radians(omega)));

  // Geocentric unit direction in the equatorial frame of date.
  //   x = cos(lambda)
  //   y = cos(epsilon) * sin(lambda)
  //   z = sin(epsilon) * sin(lambda)
  final cosLambda = math.cos(lambda);
  final sinLambda = math.sin(lambda);
  final ux = cosLambda;
  final uy = math.cos(epsilon) * sinLambda;
  final uz = math.sin(epsilon) * sinLambda;

  final direction = Vector3(ux, uy, uz);

  final rKm = rAu * astronomicalUnitKm;
  final position = Vector3(ux * rKm, uy * rKm, uz * rKm);

  return SunPosition(positionKm: position, direction: direction);
}
