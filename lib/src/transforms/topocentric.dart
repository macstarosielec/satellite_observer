// Internal L2 entry points: TEME state + observer -> look-angle / sub-point.

import 'package:satellite_observer/src/domain/eci_state.dart';
import 'package:satellite_observer/src/domain/failures.dart';
import 'package:satellite_observer/src/domain/geo/angles.dart';
import 'package:satellite_observer/src/domain/geo/observer.dart';
import 'package:satellite_observer/src/domain/look_angle.dart';
import 'package:satellite_observer/src/domain/sub_point.dart';
import 'package:satellite_observer/src/transforms/ecef_to_topocentric.dart';
import 'package:satellite_observer/src/transforms/eci_to_ecef.dart';
import 'package:satellite_observer/src/transforms/geodetic.dart';
import 'package:satellite_observer/src/transforms/range_rate.dart';

/// Computes the topocentric [LookAngle] from an observer to a satellite.
///
/// Runs the full L2 chain (ADR-4): TEME [state] -> ECEF (rotate by GMST) ->
/// observer-relative vector -> SEZ frame -> azimuth/elevation/slant-range, plus
/// the line-of-sight range rate. Angles are returned in degrees (ADR-13) and
/// the result's `utc` matches the state's.
///
/// Throws a [GeometryException] for degenerate geometry where the slant range
/// is zero (e.g. the satellite coincides with the observer), which would make
/// the azimuth/elevation undefined.
///
/// Library-private; surfaced through the public facade as
/// `SatelliteObserver.lookAngleAt`.
LookAngle topocentricLookAngle(EciState state, Observer observer) {
  final satEcef = temeToEcef(state);
  final observerEcef = observerToEcef(observer);

  // `ecefToTopocentric` throws [GeometryException] on a zero/non-finite slant
  // range before any NaN-bearing result is constructed; it propagates here.
  final topo = ecefToTopocentric(satEcef.position, observer, observerEcef);

  final rate = rangeRate(topo.sezRelative, satEcef.velocity, observer);

  return LookAngle(
    azimuthDeg: degrees(topo.azimuthRad),
    elevationDeg: degrees(topo.elevationRad),
    rangeKm: topo.rangeKm,
    rangeRateKmS: rate,
    utc: state.utc,
  );
}

/// Computes the sub-satellite point (geodetic point beneath the satellite).
///
/// Runs TEME [state] -> ECEF (rotate by GMST) -> WGS-84 geodetic (FR-8). The
/// returned [SubSatellitePoint] carries geodetic latitude/longitude in degrees
/// and altitude above the ellipsoid in kilometres.
///
/// Library-private; surfaced through the public facade as
/// `SatelliteObserver.subPointAt`.
SubSatellitePoint subSatellitePoint(EciState state) {
  final satEcef = temeToEcef(state);
  return ecefToGeodetic(satEcef.position);
}
