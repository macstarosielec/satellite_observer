// Self-consistent geometric unit tests for the L2 topocentric stage.
//
// These are deliberately INDEPENDENT of the Skyfield reference gate: they use
// closed-form geometric constructions (a satellite placed at a known SEZ
// direction, or straight above the observer) so the expected azimuth /
// elevation / range follow from the geometry alone, not from a reference
// fixture. They pin down the SEZ rotation sign handling, the azimuth quadrant
// mapping and wrap, the zero-range GeometryException path, and the negative
// elevation (below-horizon) behaviour.

import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:satellite_observer/src/domain/geo/angles.dart';
import 'package:satellite_observer/src/transforms/ecef_to_topocentric.dart';
import 'package:satellite_observer/src/transforms/geodetic.dart';
import 'package:satellite_observer/src/transforms/topocentric.dart';
import 'package:test/test.dart';

/// Builds an ECEF relative vector from SEZ `(south, east, zenith)` components
/// at the observer geodetic [latDeg]/[lonDeg], i.e. the transpose of the SEZ
/// rotation (the matrix is orthonormal, so the inverse is its transpose).
Vector3 sezToEcefRelative(
  double south,
  double east,
  double zenith,
  double latDeg,
  double lonDeg,
) {
  final lat = radians(latDeg);
  final lon = radians(lonDeg);
  final sinLat = math.sin(lat);
  final cosLat = math.cos(lat);
  final sinLon = math.sin(lon);
  final cosLon = math.cos(lon);

  final dx = sinLat * cosLon * south - sinLon * east + cosLat * cosLon * zenith;
  final dy = sinLat * sinLon * south + cosLon * east + cosLat * sinLon * zenith;
  final dz = -cosLat * south + sinLat * zenith;
  return Vector3(dx, dy, dz);
}

void main() {
  group('topocentricLookAngle - degenerate geometry', () {
    test('a non-finite state position throws GeometryException (no NaN result)',
        () {
      final observer = Observer(
        latitudeDeg: 52.2297,
        longitudeDeg: 21.0122,
        altitudeMeters: 100,
      );

      // A non-finite TEME position propagates to a non-finite slant range; the
      // guard must surface a GeometryException rather than return a NaN/Inf
      // LookAngle. A NaN component is used (not a contrived coincident
      // position) so the trigger is exact and platform-independent: a
      // bit-exact zero range would depend on non-portable trig rounding.
      final state = EciState(
        position: const Vector3(double.nan, 0, 0),
        velocity: const Vector3(0, 0, 0),
        utc: DateTime.utc(2000, 1, 1, 12),
      );

      expect(
        () => topocentricLookAngle(state, observer),
        throwsA(isA<GeometryException>()),
      );
    });

    test('ecefToTopocentric throws on a coincident position (zero range)', () {
      final observer = Observer(latitudeDeg: 10, longitudeDeg: 20);
      final observerEcef = observerToEcef(observer);
      expect(
        () => ecefToTopocentric(observerEcef, observer, observerEcef),
        throwsA(isA<GeometryException>()),
      );
    });
  });

  group('ecefToTopocentric - zenith (overhead)', () {
    test('satellite straight above (northern observer): el ~ 90, range ~ alt',
        () {
      final observer = Observer(
        latitudeDeg: 52.2297,
        longitudeDeg: 21.0122,
        altitudeMeters: 100,
      );
      final observerEcef = observerToEcef(observer);
      // Straight up along the geodetic normal = same lat/lon, +500 km altitude.
      final satEcef = observerToEcef(
        Observer(
          latitudeDeg: 52.2297,
          longitudeDeg: 21.0122,
          altitudeMeters: 100 + 500000,
        ),
      );

      final topo = ecefToTopocentric(satEcef, observer, observerEcef);
      expect(degrees(topo.elevationRad), closeTo(90, 1e-3));
      expect(topo.rangeKm, closeTo(500, 1e-3));
    });
  });

  group('ecefToTopocentric - southern-hemisphere observer', () {
    test('overhead satellite at Sydney (lat -33.9): el ~ 90', () {
      // Negative latitude exercises the sinLat/cosLat sign handling in the SEZ
      // rotation; an overhead satellite must still read elevation ~ 90.
      final observer = Observer(
        latitudeDeg: -33.9,
        longitudeDeg: 151.2,
        altitudeMeters: 20,
      );
      final observerEcef = observerToEcef(observer);
      final satEcef = observerToEcef(
        Observer(
          latitudeDeg: -33.9,
          longitudeDeg: 151.2,
          altitudeMeters: 20 + 500000,
        ),
      );

      final topo = ecefToTopocentric(satEcef, observer, observerEcef);
      expect(degrees(topo.elevationRad), closeTo(90, 1e-3));
      expect(topo.rangeKm, closeTo(500, 1e-3));
    });
  });

  group('ecefToTopocentric - azimuth quadrants and wrap', () {
    final observer = Observer(latitudeDeg: 0, longitudeDeg: 0);
    final observerEcef = observerToEcef(observer);

    // Each direction is placed slightly above the horizon (small +zenith) at a
    // few hundred km horizontal offset, so azimuth is unambiguous.
    //
    // SEZ azimuth = atan2(east, -south):
    //   due North -> south < 0, east = 0  -> az 0
    //   due East  -> east  > 0, south = 0 -> az 90
    //   due South -> south > 0, east = 0  -> az 180
    //   due West  -> east  < 0, south = 0 -> az 270
    const horiz = 300.0;
    const up = 30.0;

    void expectAzimuth(double south, double east, double expectedAzDeg) {
      final rel = sezToEcefRelative(south, east, up, 0, 0);
      final satEcef = Vector3(
        observerEcef.x + rel.x,
        observerEcef.y + rel.y,
        observerEcef.z + rel.z,
      );
      final topo = ecefToTopocentric(satEcef, observer, observerEcef);
      // Smallest signed difference handles the 0/360 seam at North.
      var diff = (degrees(topo.azimuthRad) - expectedAzDeg) % 360.0;
      if (diff > 180.0) diff -= 360.0;
      if (diff < -180.0) diff += 360.0;
      expect(
        diff.abs(),
        lessThan(1e-6),
        reason: 'azimuth for SEZ (S=$south, E=$east) should be $expectedAzDeg',
      );
      // Result must always be normalised to [0, 360).
      expect(degrees(topo.azimuthRad), greaterThanOrEqualTo(0.0));
      expect(degrees(topo.azimuthRad), lessThan(360.0));
    }

    test('due North -> azimuth ~ 0 (handles the 0/360 seam)', () {
      expectAzimuth(-horiz, 0, 0);
    });

    test('due East -> azimuth ~ 90', () {
      expectAzimuth(0, horiz, 90);
    });

    test('due South -> azimuth ~ 180', () {
      expectAzimuth(horiz, 0, 180);
    });

    test('due West -> azimuth ~ 270', () {
      expectAzimuth(0, -horiz, 270);
    });
  });

  group('ecefToTopocentric - negative elevation (below horizon)', () {
    test('satellite below the local horizon: elevation < 0, range > 0', () {
      final observer = Observer(latitudeDeg: 0, longitudeDeg: 0);
      final observerEcef = observerToEcef(observer);
      // Pure negative-zenith offset: directly below the observer.
      final rel = sezToEcefRelative(0, 0, -300, 0, 0);
      final satEcef = Vector3(
        observerEcef.x + rel.x,
        observerEcef.y + rel.y,
        observerEcef.z + rel.z,
      );

      final topo = ecefToTopocentric(satEcef, observer, observerEcef);
      expect(degrees(topo.elevationRad), lessThan(0));
      expect(topo.rangeKm, greaterThan(0));
    });
  });
}
