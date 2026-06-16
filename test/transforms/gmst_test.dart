import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:satellite_observer/src/domain/time/gmst.dart';
import 'package:test/test.dart';

/// Validates the Dart IAU-1982 GMST against an independent Skyfield reference
/// (`t.gmst * 15` degrees). Tolerance: < 1e-3 deg.
///
/// The only model differences from Skyfield's mean sidereal time are the same
/// IAU-1982 polynomial fed UTC-as-UT1 (DUT1 < 0.9 s -> a few arc-seconds,
/// ~3e-4 deg worst case), so 1e-3 deg is a tight, honest bound.
void main() {
  group('greenwichMeanSiderealTime - vs Skyfield gmst_ref.json', () {
    late List<Map<String, dynamic>> samples;

    setUpAll(() async {
      final raw = await File(
        'test/fixtures/transforms/gmst_ref.json',
      ).readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      samples = (json['samples'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    test('matches reference within 1e-3 deg at every instant', () {
      expect(samples, isNotEmpty);
      var worst = 0.0;
      for (final s in samples) {
        final utc = DateTime.parse(s['utc'] as String);
        final expectedDeg = (s['gmstDeg'] as num).toDouble();

        final gotRad = greenwichMeanSiderealTime(utc);
        final gotDeg = gotRad * 180.0 / math.pi;

        // Smallest signed angular difference, accounting for 360 wrap.
        var diff = (gotDeg - expectedDeg) % 360.0;
        if (diff > 180.0) diff -= 360.0;
        if (diff < -180.0) diff += 360.0;
        worst = math.max(worst, diff.abs());

        expect(
          diff.abs(),
          lessThan(1e-3),
          reason: 'GMST mismatch at ${s['utc']}: '
              'got $gotDeg deg, expected $expectedDeg deg',
        );
      }
      // Diagnostic worst-case output: prints the measured deviation so a
      // regression near the 1e-3 deg bound is visible in CI logs.
      // ignore: avoid_print
      print('GMST worst-case deviation: '
          '${worst.toStringAsExponential(3)} deg');
    });

    test('result is always normalised to [0, 2*pi)', () {
      for (final s in samples) {
        final utc = DateTime.parse(s['utc'] as String);
        final rad = greenwichMeanSiderealTime(utc);
        expect(rad, greaterThanOrEqualTo(0.0));
        expect(rad, lessThan(2 * math.pi));
      }
    });
  });
}
