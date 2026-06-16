import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

void main() {
  group('Observer - construction', () {
    test('stores geodetic coordinates and defaults altitude to 0', () {
      final obs = Observer(latitudeDeg: 52.2297, longitudeDeg: 21.0122);
      expect(obs.latitudeDeg, 52.2297);
      expect(obs.longitudeDeg, 21.0122);
      expect(obs.altitudeMeters, 0);
    });

    test('accepts the inclusive boundaries', () {
      expect(
        () => Observer(latitudeDeg: 90, longitudeDeg: 180),
        returnsNormally,
      );
      expect(
        () => Observer(latitudeDeg: -90, longitudeDeg: -180),
        returnsNormally,
      );
    });
  });

  group('Observer - validation', () {
    test('latitude above 90 throws ArgumentError', () {
      expect(
        () => Observer(latitudeDeg: 90.1, longitudeDeg: 0),
        throwsArgumentError,
      );
    });

    test('latitude below -90 throws ArgumentError', () {
      expect(
        () => Observer(latitudeDeg: -90.1, longitudeDeg: 0),
        throwsArgumentError,
      );
    });

    test('longitude above 180 throws ArgumentError', () {
      expect(
        () => Observer(latitudeDeg: 0, longitudeDeg: 180.1),
        throwsArgumentError,
      );
    });

    test('longitude below -180 throws ArgumentError', () {
      expect(
        () => Observer(latitudeDeg: 0, longitudeDeg: -180.1),
        throwsArgumentError,
      );
    });

    test('NaN latitude throws ArgumentError', () {
      expect(
        () => Observer(latitudeDeg: double.nan, longitudeDeg: 0),
        throwsArgumentError,
      );
    });

    test('NaN longitude throws ArgumentError', () {
      expect(
        () => Observer(latitudeDeg: 0, longitudeDeg: double.nan),
        throwsArgumentError,
      );
    });
  });

  group('Observer - value semantics', () {
    test('equal observers are == and share a hashCode', () {
      final a = Observer(latitudeDeg: 1, longitudeDeg: 2, altitudeMeters: 3);
      final b = Observer(latitudeDeg: 1, longitudeDeg: 2, altitudeMeters: 3);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing altitude breaks equality', () {
      final a = Observer(latitudeDeg: 1, longitudeDeg: 2);
      final b = Observer(latitudeDeg: 1, longitudeDeg: 2, altitudeMeters: 5);
      expect(a, isNot(equals(b)));
    });

    test('toString includes the coordinates', () {
      final s = Observer(latitudeDeg: 1, longitudeDeg: 2).toString();
      expect(s, contains('1'));
      expect(s, contains('2'));
    });
  });
}
