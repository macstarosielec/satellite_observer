// WGS-84 geodetic <-> ECEF conversions (library-private).

import 'dart:math' as math;

import 'package:satellite_observer/src/domain/geo/angles.dart';
import 'package:satellite_observer/src/domain/geo/observer.dart';
import 'package:satellite_observer/src/domain/geo/vector3.dart';
import 'package:satellite_observer/src/domain/sub_point.dart';

/// WGS-84 semi-major axis (equatorial radius), in kilometres.
const double wgs84SemiMajorAxisKm = 6378.137;

/// WGS-84 flattening.
const double wgs84Flattening = 1.0 / 298.257223563;

/// WGS-84 first eccentricity squared, `e^2 = f * (2 - f)`.
const double wgs84EccentricitySquared =
    wgs84Flattening * (2.0 - wgs84Flattening);

/// Converts an [observer]'s geodetic position to an ECEF position (km).
///
/// Uses the standard ellipsoidal formula on the WGS-84 ellipsoid:
///
/// ```text
/// N = a / sqrt(1 - e^2 * sin^2(lat))
/// x = (N + h) * cos(lat) * cos(lon)
/// y = (N + h) * cos(lat) * sin(lon)
/// z = (N * (1 - e^2) + h) * sin(lat)
/// ```
///
/// where `a` is [wgs84SemiMajorAxisKm], `e^2` is [wgs84EccentricitySquared],
/// `h` is the observer altitude (converted from metres to kilometres), and
/// `lat`/`lon` are the geodetic latitude/longitude in radians.
Vector3 observerToEcef(Observer observer) {
  final lat = radians(observer.latitudeDeg);
  final lon = radians(observer.longitudeDeg);
  final hKm = observer.altitudeMeters / 1000.0;

  final sinLat = math.sin(lat);
  final cosLat = math.cos(lat);
  final n = wgs84SemiMajorAxisKm /
      math.sqrt(1.0 - wgs84EccentricitySquared * sinLat * sinLat);

  final x = (n + hKm) * cosLat * math.cos(lon);
  final y = (n + hKm) * cosLat * math.sin(lon);
  final z = (n * (1.0 - wgs84EccentricitySquared) + hKm) * sinLat;

  return Vector3(x, y, z);
}

/// Converts an ECEF position [ecefKm] (km) to a WGS-84 geodetic point.
///
/// Uses Bowring's closed-form approximation, which converges to better than a
/// millimetre for near-Earth altitudes in a single pass. Longitude comes
/// directly from `atan2(y, x)`. The returned [SubSatellitePoint] carries
/// geodetic latitude/longitude in degrees and altitude above the ellipsoid in
/// kilometres; longitude is normalised to `[-180, 180)`.
SubSatellitePoint ecefToGeodetic(Vector3 ecefKm) {
  const a = wgs84SemiMajorAxisKm;
  const e2 = wgs84EccentricitySquared;
  const b = a * (1.0 - wgs84Flattening);
  // Second eccentricity squared.
  const ep2 = (a * a - b * b) / (b * b);

  final x = ecefKm.x;
  final y = ecefKm.y;
  final z = ecefKm.z;

  final lon = math.atan2(y, x);
  final p = math.sqrt(x * x + y * y);

  // Bowring's auxiliary angle.
  final theta = math.atan2(z * a, p * b);
  final sinTheta = math.sin(theta);
  final cosTheta = math.cos(theta);

  final lat = math.atan2(
    z + ep2 * b * sinTheta * sinTheta * sinTheta,
    p - e2 * a * cosTheta * cosTheta * cosTheta,
  );

  final sinLat = math.sin(lat);
  final n = a / math.sqrt(1.0 - e2 * sinLat * sinLat);

  // Height: robust near the poles by using z / sin(lat) when far from equator.
  final cosLat = math.cos(lat);
  final double height;
  if (cosLat.abs() < 1e-12) {
    height = z.abs() - b;
  } else {
    height = p / cosLat - n;
  }

  return SubSatellitePoint(
    latitudeDeg: degrees(lat),
    longitudeDeg: degrees(normalizePi(lon)),
    altitudeKm: height,
  );
}
