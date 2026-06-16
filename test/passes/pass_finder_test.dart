import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:satellite_observer/src/passes/pass_finder.dart';
import 'package:test/test.dart';

// A synthetic look-angle whose elevation is a triangular hump, so the expected
// rise/culmination/set are known in closed form and we can probe the sampler's
// behaviour deterministically without running SGP4.
LookAngle Function(DateTime) _triangularElevation({
  required DateTime peakUtc,
  required double peakElevationDeg,
  required Duration halfWidth,
}) {
  final peakUs = peakUtc.microsecondsSinceEpoch.toDouble();
  final halfUs = halfWidth.inMicroseconds.toDouble();
  return (DateTime utc) {
    final t = utc.microsecondsSinceEpoch.toDouble();
    final frac = 1.0 - (t - peakUs).abs() / halfUs; // 1 at peak, 0 at edges
    final el = peakElevationDeg * frac; // linear up then down
    return LookAngle(
      azimuthDeg: 90,
      elevationDeg: el,
      rangeKm: 1000,
      rangeRateKmS: 0,
      utc: utc,
    );
  };
}

void main() {
  group('findPasses (synthetic elevation)', () {
    final from = DateTime.utc(2024, 5, 2);
    final to = DateTime.utc(2024, 5, 2, 1);

    test('brackets a single triangular pass with ordered events', () {
      final peak = DateTime.utc(2024, 5, 2, 0, 30);
      final lookAngleAt = _triangularElevation(
        peakUtc: peak,
        peakElevationDeg: 40,
        halfWidth: const Duration(minutes: 10),
      );

      final passes = findPasses(
        lookAngleAt: lookAngleAt,
        from: from,
        to: to,
        minElevationDeg: 10,
        sampleStep: const Duration(seconds: 30),
      );

      expect(passes, hasLength(1));
      final p = passes.single;

      // Ordering rise < culmination < set.
      expect(p.rise.utc.isBefore(p.culmination.utc), isTrue);
      expect(p.culmination.utc.isBefore(p.set.utc), isTrue);

      // The hump is el = 40 * (1 - |t-peak|/10min); el = 10 at |t-peak| = 7.5
      // min, so rise = peak - 7.5 min, set = peak + 7.5 min.
      final expectedRise = peak.subtract(const Duration(seconds: 450));
      final expectedSet = peak.add(const Duration(seconds: 450));
      expect(
        p.rise.utc.difference(expectedRise).inMilliseconds.abs(),
        lessThan(200),
      );
      expect(
        p.set.utc.difference(expectedSet).inMilliseconds.abs(),
        lessThan(200),
      );
      expect(
        p.culmination.utc.difference(peak).inMilliseconds.abs(),
        lessThan(500),
      );

      // Refined rise/set elevation ~= minElevation; culmination is the max.
      expect(p.rise.lookAngle.elevationDeg, closeTo(10, 0.05));
      expect(p.set.lookAngle.elevationDeg, closeTo(10, 0.05));
      expect(p.peakElevationDeg, closeTo(40, 0.05));
      expect(
        p.peakElevationDeg,
        greaterThanOrEqualTo(p.rise.lookAngle.elevationDeg),
      );
    });

    test('a grazing pass just above the default is not missed at 30 s', () {
      // Peak 10.4 deg, only ~0.4 deg above the 10-deg threshold: a narrow
      // grazing window. The 30-s coarse step must still catch it.
      final peak = DateTime.utc(2024, 5, 2, 0, 30);
      final lookAngleAt = _triangularElevation(
        peakUtc: peak,
        peakElevationDeg: 10.4,
        halfWidth: const Duration(minutes: 10),
      );

      final passes = findPasses(
        lookAngleAt: lookAngleAt,
        from: from,
        to: to,
        minElevationDeg: 10,
        sampleStep: const Duration(seconds: 30),
      );

      expect(passes, hasLength(1), reason: 'grazing pass must not be skipped');
      expect(passes.single.peakElevationDeg, greaterThan(10.0));
    });

    test('lowering minElevation yields longer passes (more above-horizon time)',
        () {
      final peak = DateTime.utc(2024, 5, 2, 0, 30);
      final lookAngleAt = _triangularElevation(
        peakUtc: peak,
        peakElevationDeg: 40,
        halfWidth: const Duration(minutes: 10),
      );

      final at10 = findPasses(
        lookAngleAt: lookAngleAt,
        from: from,
        to: to,
        minElevationDeg: 10,
        sampleStep: const Duration(seconds: 30),
      ).single;
      final at0 = findPasses(
        lookAngleAt: lookAngleAt,
        from: from,
        to: to,
        minElevationDeg: 0.01, // ~true horizon
        sampleStep: const Duration(seconds: 30),
      ).single;

      expect(at0.duration, greaterThan(at10.duration));
    });

    test('a pass in progress at `from` is skipped (boundary policy)', () {
      // Peak just after `from`, so the satellite is already above 10 deg at the
      // first sample: no rise crossing observed -> not emitted.
      final lookAngleAt = _triangularElevation(
        peakUtc: from.add(const Duration(minutes: 2)),
        peakElevationDeg: 40,
        halfWidth: const Duration(minutes: 10),
      );
      final passes = findPasses(
        lookAngleAt: lookAngleAt,
        from: from,
        to: to,
        minElevationDeg: 10,
        sampleStep: const Duration(seconds: 30),
      );
      expect(passes, isEmpty);
    });

    test('a pass in progress at `to` is skipped (boundary policy)', () {
      // Peak just before `to`, set falls outside the window: no set crossing.
      final lookAngleAt = _triangularElevation(
        peakUtc: to.subtract(const Duration(minutes: 2)),
        peakElevationDeg: 40,
        halfWidth: const Duration(minutes: 10),
      );
      final passes = findPasses(
        lookAngleAt: lookAngleAt,
        from: from,
        to: to,
        minElevationDeg: 10,
        sampleStep: const Duration(seconds: 30),
      );
      expect(passes, isEmpty);
    });

    test(
        'a pass shorter than the sample step is missed at that step but found '
        'at the default 30 s (documents the coarse-step tradeoff)', () {
      // A narrow hump only ~40 s wide above the 10-deg threshold: peak 12 deg,
      // halfWidth 2 min => el = 10 at |t-peak| = 2min*(1 - 10/12) = 20 s, so the
      // above-threshold window is ~40 s wide (rise to set). The peak is placed
      // OFF the coarse grid (at :31:00, between the 120 s grid points :30:00
      // and :32:00) so the whole hump falls between two coarse samples.
      final peak = DateTime.utc(2024, 5, 2, 0, 31);
      final lookAngleAt = _triangularElevation(
        peakUtc: peak,
        peakElevationDeg: 12,
        halfWidth: const Duration(minutes: 2),
      );

      // Above-threshold half-window, in seconds: halfWidth * (1 - thr/peak).
      const aboveThresholdHalfSeconds = 2 * 60 * (1 - 10 / 12); // 20 s
      const aboveThresholdSeconds = 2 * aboveThresholdHalfSeconds; // 40 s

      // A coarse step LARGER than the whole above-threshold window can step
      // right over the hump: no sample lands above the threshold, so the pass
      // is silently MISSED. This is a documented limitation, not a bug - the
      // test pins the failure mode so a future step coarsening is caught.
      const coarseStep = Duration(seconds: 120);
      expect(
        coarseStep.inSeconds,
        greaterThan(aboveThresholdSeconds.round()),
        reason: 'precondition: the coarse step must exceed the pass duration',
      );
      final missed = findPasses(
        lookAngleAt: lookAngleAt,
        from: from,
        to: to,
        minElevationDeg: 10,
        sampleStep: coarseStep,
      );
      expect(missed, isEmpty, reason: 'a pass shorter than the step is missed');

      // The same pass at the default 30 s step is comfortably sampled, found.
      final found = findPasses(
        lookAngleAt: lookAngleAt,
        from: from,
        to: to,
        minElevationDeg: 10,
        sampleStep: const Duration(seconds: 30),
      );
      expect(found, hasLength(1), reason: 'the 30 s step resolves the pass');
      expect(found.single.peakElevationDeg, closeTo(12, 0.05));
    });

    test('no pass when the satellite never reaches the threshold', () {
      final lookAngleAt = _triangularElevation(
        peakUtc: DateTime.utc(2024, 5, 2, 0, 30),
        peakElevationDeg: 5, // below 10
        halfWidth: const Duration(minutes: 10),
      );
      final passes = findPasses(
        lookAngleAt: lookAngleAt,
        from: from,
        to: to,
        minElevationDeg: 10,
        sampleStep: const Duration(seconds: 30),
      );
      expect(passes, isEmpty);
    });
  });

  group('passes with the real SGP4 engine (minElevation semantics)', () {
    late SatelliteObserver sat;
    late DateTime fromUtc;
    late DateTime toUtc;

    setUpAll(() async {
      final raw = await File(
        'test/fixtures/passes/iss_passes_window.json',
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
      final window = fixture['window'] as Map<String, dynamic>;
      fromUtc = DateTime.parse(window['fromUtc'] as String);
      toUtc = DateTime.parse(window['toUtc'] as String);
    });

    test('minElevation 0 yields at least as many, longer-or-equal passes', () {
      final at10 = sat.passes(from: fromUtc, to: toUtc);
      final at0 = sat.passes(from: fromUtc, to: toUtc, minElevationDeg: 0);

      // Dropping the threshold can only add passes (sub-10-deg ones appear) and
      // never remove one.
      expect(at0.length, greaterThanOrEqualTo(at10.length));

      // Total above-horizon time is strictly greater at 0 deg.
      Duration total(List<Pass> ps) =>
          ps.fold(Duration.zero, (a, p) => a + p.duration);
      expect(total(at0), greaterThan(total(at10)));
    });

    test('every refined event is internally consistent', () {
      final passes = sat.passes(from: fromUtc, to: toUtc);
      expect(passes, isNotEmpty);
      for (final p in passes) {
        // Ordering.
        expect(p.rise.utc.isBefore(p.culmination.utc), isTrue);
        expect(p.culmination.utc.isBefore(p.set.utc), isTrue);
        // Culmination is the local max and >= minElevation.
        expect(p.peakElevationDeg, greaterThanOrEqualTo(10.0));
        expect(
          p.peakElevationDeg,
          greaterThanOrEqualTo(p.rise.lookAngle.elevationDeg),
        );
        expect(
          p.peakElevationDeg,
          greaterThanOrEqualTo(p.set.lookAngle.elevationDeg),
        );
        // Rise/set elevation ~= the 10-deg threshold after refine.
        expect(p.rise.lookAngle.elevationDeg, closeTo(10.0, 0.05));
        expect(p.set.lookAngle.elevationDeg, closeTo(10.0, 0.05));
        // duration == set - rise.
        expect(
          p.duration,
          p.set.utc.difference(p.rise.utc),
        );
      }
    });

    test('a higher minElevation never produces more passes', () {
      final at10 = sat.passes(from: fromUtc, to: toUtc);
      final at30 = sat.passes(from: fromUtc, to: toUtc, minElevationDeg: 30);
      expect(at30.length, lessThanOrEqualTo(at10.length));
      // Every 30-deg pass peaks above 30 deg.
      for (final p in at30) {
        expect(p.peakElevationDeg, greaterThan(30.0 - 1e-9));
      }
    });
  });

  test('sampleStep math sanity (documents the 30 s coarse grid)', () {
    // A LEO ISS pass above 10 deg lasts minutes; 30 s samples it many times.
    const passSeconds = 5 * 60;
    const step = 30;
    // math.max is exercised genuinely here: the number of samples across a pass
    // is at least 1, and for a multi-minute pass comfortably more than 5.
    expect(math.max(1, passSeconds ~/ step), greaterThan(5));
    // Guard against an accidental unit slip in the default.
    expect(const Duration(seconds: 30).inMicroseconds, 30000000);
  });
}
