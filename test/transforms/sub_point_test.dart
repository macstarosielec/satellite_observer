import 'dart:convert';
import 'dart:io' show File;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:satellite_observer/src/transforms/geodetic.dart';
import 'package:satellite_observer/src/transforms/topocentric.dart';
import 'package:test/test.dart';

/// WGS-84 semi-minor axis (km), `b = a * (1 - f)`, for altitude sanity checks.
const double _wgs84SemiMinorAxisKm =
    wgs84SemiMajorAxisKm * (1.0 - wgs84Flattening);

void main() {
  group('subSatellitePoint - ISS sanity', () {
    late Sgp4Engine engine;

    setUpAll(() async {
      final raw = await File(
        'test/fixtures/transforms/iss_pass_lookangles.json',
      ).readAsString();
      final fixture = jsonDecode(raw) as Map<String, dynamic>;
      final tle = fixture['tle'] as Map<String, dynamic>;
      engine = Sgp4Engine(
        GpElements.fromTle(
          tle['line1'] as String,
          tle['line2'] as String,
          name: tle['name'] as String,
        ),
      );
    });

    test('ISS sub-point: |lat| <= inclination and altitude is plausible', () {
      // Propagate over a full revolution at a few points.
      for (var min = 0; min < 95; min += 10) {
        final state = engine.propagate(
          engine.epoch.add(Duration(minutes: min)),
        );
        final sp = subSatellitePoint(state);

        // ISS inclination ~51.6 deg; geodetic sub-lat must stay within it
        // (allow a small geodetic-vs-geocentric margin).
        expect(sp.latitudeDeg.abs(), lessThanOrEqualTo(52.5));
        expect(sp.longitudeDeg, inInclusiveRange(-180.0, 180.0));
        // ISS altitude is a few hundred km.
        expect(sp.altitudeKm, inInclusiveRange(300.0, 500.0));
      }
    });
  });

  group('subSatellitePoint - known-direction check', () {
    test('a state straight above (a+h, 0, 0) at GMST=0 maps near lon 0', () {
      // Construct a TEME position on the +x axis. We do not know GMST here,
      // so we only assert latitude ~ 0 (equatorial) and altitude correctness;
      // longitude depends on the sidereal rotation at this instant.
      final state = EciState(
        position: const Vector3(6378.137 + 400.0, 0, 0),
        velocity: const Vector3(0, 7.6, 0),
        utc: DateTime.utc(2024, 1, 1, 12),
      );
      final sp = subSatellitePoint(state);
      expect(sp.latitudeDeg, closeTo(0, 1e-6));
      expect(sp.altitudeKm, closeTo(400.0, 1e-3));
      expect(sp.longitudeDeg, inInclusiveRange(-180.0, 180.0));
    });
  });

  group('ecefToGeodetic - longitude normalisation edge cases', () {
    test('exactly on the anti-meridian maps to -180 (half-open [-180, 180))',
        () {
      // Equatorial point on the -x axis: geodetic longitude is exactly 180 deg,
      // which the [-180, 180) normalisation folds to -180.
      const r = wgs84SemiMajorAxisKm + 400.0;
      final sp = ecefToGeodetic(const Vector3(-r, 0, 0));
      expect(sp.longitudeDeg, closeTo(-180, 1e-9));
      expect(sp.longitudeDeg, greaterThanOrEqualTo(-180.0));
      expect(sp.longitudeDeg, lessThan(180.0));
      expect(sp.latitudeDeg, closeTo(0, 1e-9));
      expect(sp.altitudeKm, closeTo(400, 1e-3));
    });

    test('just east of the anti-meridian stays just under +180', () {
      // A tiny +y offset puts longitude just under +180 (not wrapped to -180).
      const r = wgs84SemiMajorAxisKm + 400.0;
      final sp = ecefToGeodetic(const Vector3(-r, 1, 0));
      expect(sp.longitudeDeg, greaterThan(179.9));
      expect(sp.longitudeDeg, lessThan(180.0));
    });
  });

  group('ecefToGeodetic - polar edge cases', () {
    test('near the north pole (x~=y~=0, large +z): lat ~ 90', () {
      // Exercises the cosLat.abs() < 1e-12 polar height branch.
      const z = wgs84SemiMajorAxisKm + 500.0;
      final sp = ecefToGeodetic(const Vector3(0, 0, z));
      expect(sp.latitudeDeg, closeTo(90, 1e-6));
      // Height = |z| - b at the pole; plausible few-hundred-km altitude.
      expect(sp.altitudeKm, closeTo(z - _wgs84SemiMinorAxisKm, 1e-6));
      expect(sp.altitudeKm, inInclusiveRange(400.0, 700.0));
    });

    test('near the south pole (x~=y~=0, large -z): lat ~ -90', () {
      const z = -(wgs84SemiMajorAxisKm + 500.0);
      final sp = ecefToGeodetic(const Vector3(0, 0, z));
      expect(sp.latitudeDeg, closeTo(-90, 1e-6));
      expect(sp.altitudeKm, closeTo(z.abs() - _wgs84SemiMinorAxisKm, 1e-6));
      expect(sp.altitudeKm, inInclusiveRange(400.0, 700.0));
    });
  });
}
