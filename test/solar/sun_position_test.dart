import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

import '../support/sun_altitude.dart';

/// The Meeus Sun-model gate (ADR-2): the analytic low-precision Sun altitude vs
/// an INDEPENDENT Skyfield + DE421 reference.
///
/// `tool/gen_visibility_fixtures.py` records, for a fixed Warsaw observer and a
/// 24 h sweep of UTC instants (day / twilight / night), Skyfield's GEOMETRIC
/// topocentric Sun altitude. Here we compute the Sun's topocentric altitude the
/// way the package does - the Meeus geocentric ECI Sun, rotated to ECEF by
/// GMST, into the observer's local frame - and require it to match each sample.
///
/// ## Tolerance and why
///
/// Meeus low-precision is ~arc-minute (~0.01 deg) in the Sun's direction
/// (ADR-2). The reference uses the DE421 ephemeris and apparent (aberration +
/// nutation) place. The dominant residual is the model-vs-ephemeris difference
/// plus the same arc-second frame simplifications the package already makes
/// (UT1 ~= UTC, no polar motion; ADR-4 / NG5). `0.05 deg` is a safe, honest
/// bound that comfortably covers this and is far below any twilight threshold
/// step (the gate is -6/-12/-18 deg). A failure above 0.05 deg is a real Sun
/// model bug - do NOT widen it.
void main() {
  group('Meeus Sun altitude vs Skyfield (ADR-2)', () {
    late Observer observer;
    late List<Map<String, dynamic>> samples;

    setUpAll(() async {
      final raw = await File(
        'test/fixtures/visibility/sun_altitude_ref.json',
      ).readAsString();
      final fixture = jsonDecode(raw) as Map<String, dynamic>;
      final obs = fixture['observer'] as Map<String, dynamic>;
      observer = Observer(
        latitudeDeg: (obs['latDeg'] as num).toDouble(),
        longitudeDeg: (obs['lonDeg'] as num).toDouble(),
        altitudeMeters: (obs['altM'] as num).toDouble(),
      );
      samples =
          (fixture['samples'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    test('matches every sample within 0.05 deg', () {
      // Sanity: the committed fixture must span a real day so a truncated
      // fixture cannot pass a trivial floor.
      expect(samples.length, greaterThanOrEqualTo(48));

      const tolDeg = 0.05;
      var worst = 0.0;
      for (final sample in samples) {
        final utc = DateTime.parse(sample['utc'] as String);
        final refAlt = (sample['sunAltDeg'] as num).toDouble();
        final gotAlt = sunAltitudeForTest(utc, observer);
        final diff = (gotAlt - refAlt).abs();
        worst = math.max(worst, diff);
        expect(
          diff,
          lessThan(tolDeg),
          reason: 'Sun altitude at $utc: got $gotAlt, ref $refAlt',
        );
      }

      // ignore: avoid_print
      print('Meeus Sun altitude worst-case vs Skyfield over '
          '${samples.length} samples: ${worst.toStringAsFixed(4)} deg');
    });
  });
}
