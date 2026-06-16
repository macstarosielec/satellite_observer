import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

/// The L3 reference gate (ADR-5 / FR-9): an independent Skyfield pass window.
///
/// We feed the SAME ISS TLE, the SAME Warsaw observer, the SAME 3-day window,
/// and the SAME 10-deg minimum elevation into `SatelliteObserver.passes` that
/// `tool/gen_pass_fixtures.py` gave to Skyfield's `find_events`. Both sides run
/// SGP4, so the only thing under test is the pass-finding (event bracketing +
/// root-refine).
///
/// ## Tolerances and why
///
/// Times: <= 2 s. Skyfield brackets events on its own internal sampling grid
/// then refines; we coarse-sample at 30 s and refine rise/set by bisection (to
/// ~0.1 s) and culmination by quadratic interpolation. The residual is the
/// refine precision difference plus the arc-second-level frame difference
/// (we omit polar motion; ADR-4 / NG5), which at ~1 deg/s of ISS elevation rate
/// near the horizon stays well under a second. 2 s is a safe, honest bound.
///
/// Peak elevation: <= 0.05 deg, dominated by the same arc-second frame
/// difference plus the quadratic-peak interpolation error.
///
/// If the COUNT differs, or any event is off by more than a couple of seconds,
/// that is a real pass-finder bug - do NOT widen the tolerance.
void main() {
  group('ISS passes vs Skyfield find_events (L3 reference gate)', () {
    late SatelliteObserver observerSat;
    late DateTime fromUtc;
    late DateTime toUtc;
    late double minElevationDeg;
    late List<Map<String, dynamic>> refPasses;

    setUpAll(() async {
      final raw = await File(
        'test/fixtures/passes/iss_passes_window.json',
      ).readAsString();
      final fixture = jsonDecode(raw) as Map<String, dynamic>;

      final tle = fixture['tle'] as Map<String, dynamic>;
      final obs = fixture['observer'] as Map<String, dynamic>;
      observerSat = SatelliteObserver(
        elements: GpElements.fromTle(
          tle['line1'] as String,
          tle['line2'] as String,
          name: tle['name'] as String,
        ),
        observer: Observer(
          latitudeDeg: (obs['latDeg'] as num).toDouble(),
          longitudeDeg: (obs['lonDeg'] as num).toDouble(),
          altitudeMeters: (obs['altM'] as num).toDouble(),
        ),
      );

      minElevationDeg = (fixture['minElevationDeg'] as num).toDouble();
      final window = fixture['window'] as Map<String, dynamic>;
      fromUtc = DateTime.parse(window['fromUtc'] as String);
      toUtc = DateTime.parse(window['toUtc'] as String);
      refPasses =
          (fixture['passes'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    test('matches Skyfield pass-for-pass within tolerance (no skips)', () {
      // Sanity: the committed fixture must carry a real multi-pass window so a
      // silently-truncated fixture cannot pass a low floor.
      expect(refPasses.length, greaterThanOrEqualTo(10));

      final found = observerSat.passes(
        from: fromUtc,
        to: toUtc,
        minElevationDeg: minElevationDeg,
      );

      // The headline assertion: the same number of passes.
      expect(
        found.length,
        refPasses.length,
        reason: 'pass count differs from Skyfield - a real pass-finder bug',
      );

      const timeTolSeconds = 2.0;
      const peakTolDeg = 0.05;

      var worstRise = 0.0;
      var worstCulm = 0.0;
      var worstSet = 0.0;
      var worstPeak = 0.0;

      for (var k = 0; k < refPasses.length; k++) {
        final ref = refPasses[k];
        final pass = found[k];

        final refRise = DateTime.parse(ref['riseUtc'] as String);
        final refCulm = DateTime.parse(ref['culminationUtc'] as String);
        final refSet = DateTime.parse(ref['setUtc'] as String);
        final refPeak = (ref['peakElevationDeg'] as num).toDouble();

        final riseDiff =
            pass.rise.utc.difference(refRise).inMicroseconds.abs() / 1e6;
        final culmDiff =
            pass.culmination.utc.difference(refCulm).inMicroseconds.abs() / 1e6;
        final setDiff =
            pass.set.utc.difference(refSet).inMicroseconds.abs() / 1e6;
        final peakDiff = (pass.peakElevationDeg - refPeak).abs();

        worstRise = math.max(worstRise, riseDiff);
        worstCulm = math.max(worstCulm, culmDiff);
        worstSet = math.max(worstSet, setDiff);
        worstPeak = math.max(worstPeak, peakDiff);

        expect(
          riseDiff,
          lessThan(timeTolSeconds),
          reason: 'pass $k rise: got ${pass.rise.utc}, ref $refRise',
        );
        expect(
          culmDiff,
          lessThan(timeTolSeconds),
          reason: 'pass $k culmination: '
              'got ${pass.culmination.utc}, ref $refCulm',
        );
        expect(
          setDiff,
          lessThan(timeTolSeconds),
          reason: 'pass $k set: got ${pass.set.utc}, ref $refSet',
        );
        expect(
          peakDiff,
          lessThan(peakTolDeg),
          reason: 'pass $k peak elevation: '
              'got ${pass.peakElevationDeg}, ref $refPeak',
        );

        // Event kinds must be correctly tagged (guards against a rise/set
        // swap that a times-only comparison would let slip through).
        expect(pass.rise.kind, PassEventKind.rise);
        expect(pass.culmination.kind, PassEventKind.culmination);
        expect(pass.set.kind, PassEventKind.set);

        // Per-pass structural sanity (also covered in pass_finder_test,
        // asserted here against the real data too).
        expect(
          pass.rise.utc.isBefore(pass.culmination.utc),
          isTrue,
          reason: 'pass $k: rise must precede culmination',
        );
        expect(
          pass.culmination.utc.isBefore(pass.set.utc),
          isTrue,
          reason: 'pass $k: culmination must precede set',
        );
      }

      // ignore: avoid_print
      print('ISS passes worst-case vs Skyfield over ${found.length} passes: '
          'rise ${worstRise.toStringAsFixed(3)} s, '
          'culm ${worstCulm.toStringAsFixed(3)} s, '
          'set ${worstSet.toStringAsFixed(3)} s, '
          'peakEl ${worstPeak.toStringAsFixed(4)} deg');
    });
  });
}
