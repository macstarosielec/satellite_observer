import 'package:satellite_observer/src/domain/geo/observer.dart';
import 'package:satellite_observer/src/domain/geo/vector3.dart';
import 'package:satellite_observer/src/transforms/geodetic.dart';
import 'package:test/test.dart';

void main() {
  group('observerToEcef - known anchors', () {
    test('equator on prime meridian: x ~= a + h, y ~= 0, z ~= 0', () {
      final ecef = observerToEcef(
        Observer(latitudeDeg: 0, longitudeDeg: 0),
      );
      expect(ecef.x, closeTo(wgs84SemiMajorAxisKm, 1e-6));
      expect(ecef.y, closeTo(0, 1e-9));
      expect(ecef.z, closeTo(0, 1e-9));
    });

    test('equator on prime meridian with altitude adds to x', () {
      final ecef = observerToEcef(
        Observer(latitudeDeg: 0, longitudeDeg: 0, altitudeMeters: 1000),
      );
      expect(ecef.x, closeTo(wgs84SemiMajorAxisKm + 1.0, 1e-6));
      expect(ecef.y, closeTo(0, 1e-9));
      expect(ecef.z, closeTo(0, 1e-9));
    });

    test('north pole: x ~= 0, y ~= 0, z ~= polar radius b', () {
      const b = wgs84SemiMajorAxisKm * (1.0 - wgs84Flattening);
      final ecef = observerToEcef(
        Observer(latitudeDeg: 90, longitudeDeg: 0),
      );
      expect(ecef.x, closeTo(0, 1e-9));
      expect(ecef.y, closeTo(0, 1e-9));
      expect(ecef.z, closeTo(b, 1e-6));
    });

    test('equator at 90 deg E: y ~= a, x ~= 0', () {
      final ecef = observerToEcef(
        Observer(latitudeDeg: 0, longitudeDeg: 90),
      );
      expect(ecef.x, closeTo(0, 1e-9));
      expect(ecef.y, closeTo(wgs84SemiMajorAxisKm, 1e-6));
      expect(ecef.z, closeTo(0, 1e-9));
    });
  });

  group('geodetic <-> ECEF round-trip', () {
    final cases = <Observer>[
      Observer(latitudeDeg: 0, longitudeDeg: 0),
      Observer(
        latitudeDeg: 52.2297,
        longitudeDeg: 21.0122,
        altitudeMeters: 100,
      ),
      Observer(
        latitudeDeg: -33.8688,
        longitudeDeg: 151.2093,
        altitudeMeters: 58,
      ),
      Observer(latitudeDeg: 89.9, longitudeDeg: -45),
      Observer(latitudeDeg: -89.9, longitudeDeg: 179.9, altitudeMeters: 250),
      Observer(latitudeDeg: 45, longitudeDeg: -120, altitudeMeters: 4000),
    ];

    for (final obs in cases) {
      test('round-trips ${obs.latitudeDeg},${obs.longitudeDeg}', () {
        final ecef = observerToEcef(obs);
        final geo = ecefToGeodetic(ecef);

        expect(geo.latitudeDeg, closeTo(obs.latitudeDeg, 1e-6));
        // Compare longitude modulo 360 to be safe near +/-180.
        var lonDiff = (geo.longitudeDeg - obs.longitudeDeg) % 360.0;
        if (lonDiff > 180.0) lonDiff -= 360.0;
        if (lonDiff < -180.0) lonDiff += 360.0;
        expect(lonDiff.abs(), lessThan(1e-6));
        // Altitude back to within 1 mm (1e-6 km).
        expect(geo.altitudeKm, closeTo(obs.altitudeMeters / 1000.0, 1e-6));
      });
    }
  });

  group('ecefToGeodetic - direct correctness', () {
    test('point above the equator at prime meridian', () {
      // 100 km straight up at lat 0, lon 0.
      const ecef = Vector3(wgs84SemiMajorAxisKm + 100.0, 0, 0);
      final geo = ecefToGeodetic(ecef);
      expect(geo.latitudeDeg, closeTo(0, 1e-9));
      expect(geo.longitudeDeg, closeTo(0, 1e-9));
      expect(geo.altitudeKm, closeTo(100.0, 1e-6));
    });

    test('longitude is read directly from atan2(y, x)', () {
      final ecef = observerToEcef(
        Observer(latitudeDeg: 10, longitudeDeg: -73.5),
      );
      final geo = ecefToGeodetic(ecef);
      expect(geo.longitudeDeg, closeTo(-73.5, 1e-6));
    });

    test('north pole point maps to lat ~= 90', () {
      const b = wgs84SemiMajorAxisKm * (1.0 - wgs84Flattening);
      final geo = ecefToGeodetic(const Vector3(0, 0, b + 500.0));
      expect(geo.latitudeDeg, closeTo(90, 1e-6));
      expect(geo.altitudeKm, closeTo(500.0, 1e-3));
    });
  });

  test('e^2 matches f*(2-f)', () {
    expect(
      wgs84EccentricitySquared,
      closeTo(wgs84Flattening * (2 - wgs84Flattening), 1e-18),
    );
    // Sanity: WGS-84 e^2 is approximately 0.00669438.
    expect(wgs84EccentricitySquared, closeTo(0.00669437999, 1e-9));
  });
}
