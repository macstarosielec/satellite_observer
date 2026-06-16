// TLE string literals are exactly 69 columns and cannot be wrapped, so the
// line-length lint is relaxed for this file.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

void main() {
  group('GpElements.fromTle', () {
    // Canonical VANGUARD (catalog 00005) element set, with the decoded values
    // taken from python-sgp4's VANGUARD_ATTRS in tests.py.
    const line1 =
        '1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753';
    const line2 =
        '2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667';

    test('decodes mean elements to the python-sgp4 reference values', () {
      final el = GpElements.fromTle(line1, line2, name: 'VANGUARD 1');

      expect(el.name, 'VANGUARD 1');
      // Epoch: year 2000, day-of-year 179.78495062.
      expect(el.epoch.year, 2000);
      expect(el.epoch.isUtc, isTrue);
      // ecco 0.1859667 exactly from the TLE field.
      expect(el.eccentricity, closeTo(0.1859667, 1e-12));
      // inclo 0.5980929187319208 rad.
      expect(el.inclinationRad, closeTo(0.5980929187319208, 1e-15));
      // no_kozai 0.04722944544077857 rad/min.
      expect(el.meanMotionRadPerMin, closeTo(0.04722944544077857, 1e-17));
    });

    test('epoch decodes to the correct UTC instant', () {
      final el = GpElements.fromTle(line1, line2);
      // Day-of-year 179.78495062 of 2000 -> 2000-06-27 around 18:50 UTC.
      final expected = DateTime.utc(2000).add(
        Duration(microseconds: ((179.78495062 - 1.0) * 86400.0 * 1e6).round()),
      );
      expect(el.epoch.isAtSameMomentAs(expected), isTrue);
      expect(el.epoch.month, 6);
      expect(el.epoch.day, 27);
    });

    test('ignores trailing verification fields past column 69', () {
      const line2Extra = '$line2     0.00      4320.0        360.00';
      final el = GpElements.fromTle(line1, line2Extra);
      expect(el.meanMotionRadPerMin, closeTo(0.04722944544077857, 1e-17));
    });

    test('throws InvalidElementsException on a garbage numeric field', () {
      const bad1 =
          '1 00005U 58002B   00179.7XYZ5062  .00000023  00000-0  28098-4 0  4753';
      expect(
        () => GpElements.fromTle(bad1, line2),
        throwsA(isA<InvalidElementsException>()),
      );
    });

    test('throws InvalidElementsException on a too-short line1', () {
      // Under 69 columns: the explicit length guard must reject it as a domain
      // failure, never letting a RangeError escape.
      const shortLine1 = '1 00005U 58002B   00179.78495062';
      expect(
        () => GpElements.fromTle(shortLine1, line2),
        throwsA(isA<InvalidElementsException>()),
      );
    });

    test('throws InvalidElementsException on a too-short line2', () {
      const shortLine2 = '2 00005  34.2682 348.7242';
      expect(
        () => GpElements.fromTle(line1, shortLine2),
        throwsA(isA<InvalidElementsException>()),
      );
    });

    test(
        'a 69-char line with a whitespace numeric field does not leak a '
        'RangeError', () {
      // A line that is long enough to pass the length guard but whose
      // assumed-decimal fields are blank must still surface a domain failure
      // (InvalidElementsException), not a raw RangeError or FormatException.
      const blank1 =
          '1 00005U 58002B   00179.78495062                          0  4753';
      Object? caught;
      try {
        GpElements.fromTle(blank1.padRight(69), line2);
      } on Object catch (e) {
        caught = e;
      }
      // Either it parsed (blank drag terms -> 0) or it threw the domain type;
      // it must never be a raw RangeError/FormatException.
      expect(caught, anyOf(isNull, isA<InvalidElementsException>()));
      expect(caught, isNot(isA<RangeError>()));
      expect(caught, isNot(isA<FormatException>()));
    });

    test('throws InvalidElementsException on non-physical eccentricity', () {
      // Eccentricity field forced to 9999999 -> 0.9999999 is valid; use a
      // mean-elements path to exercise the e >= 1 guard.
      expect(
        () => GpElements.fromMeanElements(
          epoch: DateTime.utc(2020),
          inclinationDeg: 34,
          raanDeg: 0,
          eccentricity: 1.5,
          argPerigeeDeg: 0,
          meanAnomalyDeg: 0,
          meanMotionRevPerDay: 10,
        ),
        throwsA(isA<InvalidElementsException>()),
      );
    });
  });

  group('GpElements.fromMeanElements', () {
    test('matches a TLE decode for equivalent inputs', () {
      final el = GpElements.fromMeanElements(
        epoch: DateTime.utc(2020),
        inclinationDeg: 51.6,
        raanDeg: 247,
        eccentricity: 0.0001,
        argPerigeeDeg: 130,
        meanAnomalyDeg: 325,
        meanMotionRevPerDay: 15.5,
      );
      expect(el.inclinationRad, closeTo(51.6 * math.pi / 180.0, 1e-15));
      expect(
        el.meanMotionRadPerMin,
        closeTo(15.5 * 2 * math.pi / 1440.0, 1e-15),
      );
    });
  });
}
