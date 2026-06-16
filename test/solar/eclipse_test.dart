import 'dart:convert';
import 'dart:io' show File;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:satellite_observer/src/solar/eclipse.dart';
import 'package:test/test.dart';

/// The geometric eclipse gate (ADR-6, FR-13): the Dart conical-umbra sunlit
/// test vs Skyfield's `is_sunlit` (DE421), sample-by-sample across two ISS
/// passes.
///
/// ## The guard band and why it exists
///
/// The package uses the analytic Meeus Sun direction (~arc-minute) and a
/// geometric conical umbra; Skyfield uses the DE421 ephemeris. Near the
/// umbra-grazing boundary the ~arc-minute Sun-direction difference shifts the
/// sunlit<->eclipsed CROSSING INSTANT by seconds to a few tens of seconds. So
/// the booleans are allowed to disagree ONLY within +/- 30 s (the guard band)
/// of a reference transition (a sample adjacent in time to a `sunlit` flip).
/// Outside
/// that band the Dart boolean MUST equal Skyfield's. This is the documented P4
/// eclipse-tolerance caveat - we do NOT assert the exact crossing instant, and
/// we do NOT widen the band to mask a real disagreement away from a crossing.
void main() {
  group('Eclipse geometry unit cases (ADR-6)', () {
    // Sun along +X; the default sunDistanceKm is one AU (astronomicalUnitKm),
    // which is exactly the geometry we want, so it is left as the default.
    const sunDir = Vector3(1, 0, 0);
    const r = 6778.0; // ~400 km altitude

    test('a satellite on the sunward side is always sunlit', () {
      expect(isSunlit(const Vector3(r, 0, 0), sunDir), isTrue);
    });

    test('a satellite directly behind Earth (on the axis) is eclipsed', () {
      // Anti-solar, on the Earth-Sun axis: well inside the umbra at LEO.
      expect(isSunlit(const Vector3(-r, 0, 0), sunDir), isFalse);
    });

    test('a satellite anti-solar but far off the axis is sunlit', () {
      // Anti-solar in X but displaced far in Y (above the shadow cylinder).
      expect(isSunlit(const Vector3(-1000, r, 0), sunDir), isTrue);
    });

    test('the umbra terminator near Earth radius flips sunlit/eclipsed', () {
      // Just behind Earth: a point inside R_earth of the axis is eclipsed,
      // one well outside is sunlit (umbra radius ~6377.7 km at x=-100 km).
      expect(
        isSunlit(const Vector3(-100, 6000, 0), sunDir),
        isFalse,
        reason: '6000 km < Earth radius from axis just behind Earth: eclipsed',
      );
      expect(
        isSunlit(const Vector3(-100, 6500, 0), sunDir),
        isTrue,
        reason: '6500 km > Earth radius from axis: outside the umbra, sunlit',
      );
    });

    test('a degenerate (zero) Sun direction is treated as sunlit', () {
      expect(isSunlit(const Vector3(-r, 0, 0), const Vector3(0, 0, 0)), isTrue);
    });
  });

  group('Eclipse (is_sunlit) vs Skyfield (ADR-6)', () {
    late SatelliteObserver sat;
    late List<Map<String, dynamic>> passes;

    setUpAll(() async {
      final raw = await File(
        'test/fixtures/visibility/iss_visibility_ref.json',
      ).readAsString();
      final fixture = jsonDecode(raw) as Map<String, dynamic>;
      final tle = fixture['tle'] as Map<String, dynamic>;
      final obs = fixture['observer'] as Map<String, dynamic>;
      sat = SatelliteObserver(
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
      passes =
          (fixture['passes'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    const guardBandSeconds = 30.0;

    test('sunlit boolean matches Skyfield outside a +/- 30 s crossing band',
        () {
      expect(passes.length, 2);

      var totalSamples = 0;
      var agreements = 0;
      var disagreementsInBand = 0;
      var worstTransitionShiftS = 0.0;

      for (var p = 0; p < passes.length; p++) {
        final samples = (passes[p]['samples'] as List<dynamic>)
            .cast<Map<String, dynamic>>();

        // Reference times and flags.
        final times = samples
            .map((s) => DateTime.parse(s['utc'] as String))
            .toList(growable: false);
        final refSunlit =
            samples.map((s) => s['sunlit'] as bool).toList(growable: false);

        // Indices adjacent to a reference sunlit<->eclipsed transition.
        final transitionTimes = <DateTime>[];
        for (var i = 1; i < refSunlit.length; i++) {
          if (refSunlit[i] != refSunlit[i - 1]) {
            // The crossing lies between sample i-1 and i; record both bounds.
            transitionTimes
              ..add(times[i - 1])
              ..add(times[i]);
          }
        }

        bool nearTransition(DateTime t) {
          for (final tt in transitionTimes) {
            final dt = t.difference(tt).inMicroseconds.abs() / 1e6;
            if (dt <= guardBandSeconds) return true;
          }
          return false;
        }

        for (var i = 0; i < samples.length; i++) {
          totalSamples++;
          final got = sat.isSatelliteSunlit(times[i]);
          final ref = refSunlit[i];
          if (got == ref) {
            agreements++;
          } else {
            expect(
              nearTransition(times[i]),
              isTrue,
              reason: 'pass $p sample $i at ${times[i]}: Dart sunlit=$got but '
                  'Skyfield=$ref, and this sample is NOT within '
                  '$guardBandSeconds s of a reference crossing - a real '
                  'eclipse bug, not a crossing-instant shift.',
            );
            disagreementsInBand++;
          }
        }

        // Measure the actual crossing-instant shift: for each reference
        // transition, find where the Dart boolean flips and report the gap.
        worstTransitionShiftS = _maxTransitionShift(
          times,
          refSunlit,
          sat.isSatelliteSunlit,
          worstTransitionShiftS,
        );
      }

      final agreementRate = agreements / totalSamples;
      // ignore: avoid_print
      print('Eclipse vs Skyfield: $agreements/$totalSamples agree '
          '(${(agreementRate * 100).toStringAsFixed(2)}%), '
          '$disagreementsInBand disagreement(s) inside the '
          '${guardBandSeconds.toStringAsFixed(0)} s guard band; '
          'worst crossing-instant shift '
          '${worstTransitionShiftS.toStringAsFixed(1)} s');

      // The REAL gate is the per-sample `nearTransition` assertion above: every
      // disagreement MUST fall within the guard band of a reference crossing.
      // This count bound is only a sanity ceiling - if disagreements ballooned
      // to a large fraction of the samples (even if each were "near" a
      // crossing) something would be structurally wrong. It can never reject a
      // run the per-sample gate already passed for the right reason.
      expect(disagreementsInBand, lessThan(totalSamples * 0.1));
      expect(worstTransitionShiftS, lessThanOrEqualTo(guardBandSeconds));
    });
  });
}

/// Returns the max of [running] and the largest gap (seconds) between a
/// reference sunlit transition and the nearest Dart-boolean transition.
double _maxTransitionShift(
  List<DateTime> times,
  List<bool> refSunlit,
  bool Function(DateTime) dartSunlit,
  double running,
) {
  // Dart booleans on the same grid.
  final dart = times.map(dartSunlit).toList(growable: false);

  double midpoint(int i) =>
      (times[i - 1].microsecondsSinceEpoch + times[i].microsecondsSinceEpoch) /
      2.0;

  final refCrossings = <double>[];
  final dartCrossings = <double>[];
  for (var i = 1; i < times.length; i++) {
    if (refSunlit[i] != refSunlit[i - 1]) refCrossings.add(midpoint(i));
    if (dart[i] != dart[i - 1]) dartCrossings.add(midpoint(i));
  }

  var worst = running;

  // A reference crossing with NO Dart crossing anywhere is a missing crossing -
  // a real bug, not a tiny shift. Report it as an infinite shift so the
  // `<= guardBand` assertion fails loudly rather than silently scoring 0.0 s.
  if (refCrossings.isNotEmpty && dartCrossings.isEmpty) {
    return double.infinity;
  }

  for (final rc in refCrossings) {
    var nearest = double.infinity;
    for (final dc in dartCrossings) {
      final d = (rc - dc).abs() / 1e6;
      if (d < nearest) nearest = d;
    }
    if (nearest.isFinite && nearest > worst) worst = nearest;
  }
  return worst;
}
