import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:satellite_observer/src/transforms/topocentric.dart';
import 'package:test/test.dart';

/// The reference gate (IR-2): an independent Skyfield ISS pass over Warsaw.
///
/// For each Skyfield sample we propagate the SAME embedded TLE with our SGP4
/// engine, run our own TEME -> ECEF -> SEZ chain, and compare against
/// Skyfield's geometric (no-refraction) az/el/range/range-rate.
///
/// ## Tolerances and why
///
/// Skyfield's satellite topocentric path uses GMST-based TEME -> ITRF PLUS
/// polar motion; we deliberately omit polar motion / nutation / EOP (ADR-4,
/// NG5). Polar motion is at the ~0.3 arc-second (~1e-4 deg) level, and the
/// UT1 ~= UTC simplification adds a few more arc-seconds. The measured
/// worst-case deviations over this 77-deg pass (printed below) are well inside
/// the chosen bounds:
///
/// * azimuth   < 0.02 deg
/// * elevation < 0.02 deg
/// * range     < 0.1 km
/// * range-rate< 0.01 km/s
///
/// If any sample exceeded these by a meaningful margin it would signal a real
/// frame mismatch (the classic TEME/sidereal bug) - which is exactly what this
/// independent fixture is here to catch.
void main() {
  group('ISS pass look-angles vs Skyfield (reference gate)', () {
    late Sgp4Engine engine;
    late Observer observer;
    late List<Map<String, dynamic>> samples;

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

      final obs = fixture['observer'] as Map<String, dynamic>;
      observer = Observer(
        latitudeDeg: (obs['latDeg'] as num).toDouble(),
        longitudeDeg: (obs['lonDeg'] as num).toDouble(),
        altitudeMeters: (obs['altM'] as num).toDouble(),
      );

      samples =
          (fixture['samples'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    test('every sample matches Skyfield within tolerance (no skips)', () {
      // Assert the full committed sample count so a silently-truncated fixture
      // (which would still satisfy a low floor) is caught here.
      expect(samples.length, greaterThanOrEqualTo(33));

      const azTol = 0.02;
      const elTol = 0.02;
      const rangeTol = 0.1;
      const rangeRateTol = 0.01;

      var worstAz = 0.0;
      var worstEl = 0.0;
      var worstRange = 0.0;
      var worstRangeRate = 0.0;
      var sawWrapAzimuth = false;
      var sawPositiveElevation = false;

      for (final s in samples) {
        final utc = DateTime.parse(s['utc'] as String);
        final state = engine.propagate(utc);
        final la = topocentricLookAngle(state, observer);

        // Azimuth wrap convention sanity.
        expect(la.azimuthDeg, greaterThanOrEqualTo(0.0));
        expect(la.azimuthDeg, lessThan(360.0));
        if (la.azimuthDeg > 180.0) sawWrapAzimuth = true;

        // Elevation sign: every fixture sample is above the horizon.
        expect(
          la.elevationDeg,
          greaterThan(-0.01),
          reason: 'sample at ${s['utc']} should be above the horizon',
        );
        if (la.elevationDeg > 0.0) sawPositiveElevation = true;

        final azRef = (s['azDeg'] as num).toDouble();
        final elRef = (s['elDeg'] as num).toDouble();
        final rangeRef = (s['rangeKm'] as num).toDouble();
        final rrRef = (s['rangeRateKmS'] as num).toDouble();

        // Smallest signed azimuth difference (handles the 0/360 seam).
        var azDiff = (la.azimuthDeg - azRef) % 360.0;
        if (azDiff > 180.0) azDiff -= 360.0;
        if (azDiff < -180.0) azDiff += 360.0;

        final elDiff = la.elevationDeg - elRef;
        final rangeDiff = la.rangeKm - rangeRef;
        final rrDiff = la.rangeRateKmS - rrRef;

        worstAz = math.max(worstAz, azDiff.abs());
        worstEl = math.max(worstEl, elDiff.abs());
        worstRange = math.max(worstRange, rangeDiff.abs());
        worstRangeRate = math.max(worstRangeRate, rrDiff.abs());

        expect(
          azDiff.abs(),
          lessThan(azTol),
          reason: 'azimuth at ${s['utc']}: '
              'got ${la.azimuthDeg}, ref $azRef',
        );
        expect(
          elDiff.abs(),
          lessThan(elTol),
          reason: 'elevation at ${s['utc']}: '
              'got ${la.elevationDeg}, ref $elRef',
        );
        expect(
          rangeDiff.abs(),
          lessThan(rangeTol),
          reason: 'range at ${s['utc']}: got ${la.rangeKm}, ref $rangeRef',
        );
        expect(
          rrDiff.abs(),
          lessThan(rangeRateTol),
          reason: 'range-rate at ${s['utc']}: '
              'got ${la.rangeRateKmS}, ref $rrRef',
        );
      }

      expect(
        sawWrapAzimuth,
        isTrue,
        reason: 'pass should sweep through azimuths > 180 deg',
      );
      expect(
        sawPositiveElevation,
        isTrue,
        reason: 'pass should have positive-elevation samples',
      );

      // Diagnostic worst-case output: prints the measured deviations so a
      // regression near the tolerance is visible in CI logs.
      // ignore: avoid_print
      print('ISS pass worst-case vs Skyfield over ${samples.length} samples: '
          'az ${worstAz.toStringAsFixed(5)} deg, '
          'el ${worstEl.toStringAsFixed(5)} deg, '
          'range ${worstRange.toStringAsFixed(5)} km, '
          'range-rate ${worstRangeRate.toStringAsFixed(6)} km/s');
    });

    test('look-angle utc matches the requested instant', () {
      final utc = DateTime.parse(samples.first['utc'] as String);
      final la = topocentricLookAngle(engine.propagate(utc), observer);
      expect(la.utc.isAtSameMomentAs(utc), isTrue);
    });
  });
}
