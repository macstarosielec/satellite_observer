// TLE string literals are exactly 69 columns and cannot be wrapped, so the
// line-length lint is relaxed for this file.
// ignore_for_file: lines_longer_than_80_chars

import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

void main() {
  // VANGUARD (catalog 00005) - a benign near-earth satellite.
  const line1 =
      '1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753';
  const line2 =
      '2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667';

  group('Sgp4Engine', () {
    test('exposes the element epoch', () {
      final el = GpElements.fromTle(line1, line2);
      final engine = Sgp4Engine(el);
      expect(engine.epoch.isAtSameMomentAs(el.epoch), isTrue);
    });

    test('FR-4: repeated propagate at the same instant is deterministic', () {
      final engine = Sgp4Engine(GpElements.fromTle(line1, line2));
      final t = DateTime.utc(2000, 6, 28, 12);
      final a = engine.propagate(t);
      final b = engine.propagate(t);
      expect(a, equals(b));
    });

    test('FR-4: independent engines agree for the same instant', () {
      final t = DateTime.utc(2000, 6, 28, 12);
      final a = Sgp4Engine(GpElements.fromTle(line1, line2)).propagate(t);
      final b = Sgp4Engine(GpElements.fromTle(line1, line2)).propagate(t);
      expect(a, equals(b));
    });

    test('propagate returns the requested UTC instant on the state', () {
      final engine = Sgp4Engine(GpElements.fromTle(line1, line2));
      final t = DateTime.utc(2000, 6, 28, 12, 34, 56);
      final state = engine.propagate(t);
      expect(state.utc.isAtSameMomentAs(t), isTrue);
      expect(state.position.magnitude, greaterThan(6378.0));
    });

    test('a non-UTC DateTime is normalised to UTC before propagating', () {
      final engine = Sgp4Engine(GpElements.fromTle(line1, line2));
      final local = DateTime.utc(2000, 6, 28, 12).toLocal();
      final state = engine.propagate(local);
      expect(state.utc.isUtc, isTrue);
      expect(
        state,
        equals(engine.propagate(DateTime.utc(2000, 6, 28, 12))),
      );
    });

    test('fromMeanElements matches fromTle for the same physical elements', () {
      // Build two engines for the identical physical mean elements: one from
      // the VANGUARD TLE, one from the decoded mean elements. SGP4 ignores
      // ndot/nddot, so they are omitted on the mean-elements path. The two
      // propagated states must agree (this exercises fromMeanElements, which
      // the Vallado gate does not cover).
      final fromTleEngine = Sgp4Engine(GpElements.fromTle(line1, line2));
      // Epoch: year 2000, day-of-year 179.78495062 UTC.
      final epoch = DateTime.utc(2000).add(
        Duration(microseconds: ((179.78495062 - 1.0) * 86400.0 * 1e6).round()),
      );
      final fromMeanEngine = Sgp4Engine(
        GpElements.fromMeanElements(
          epoch: epoch,
          inclinationDeg: 34.2682,
          raanDeg: 348.7242,
          eccentricity: 0.1859667,
          argPerigeeDeg: 331.7664,
          meanAnomalyDeg: 19.3264,
          meanMotionRevPerDay: 10.82419157,
          bStar: 0.000028098,
        ),
      );

      void compareAt(DateTime t) {
        final a = fromTleEngine.propagate(t);
        final b = fromMeanEngine.propagate(t);
        expect((a.position.x - b.position.x).abs(), lessThan(1e-6));
        expect((a.position.y - b.position.y).abs(), lessThan(1e-6));
        expect((a.position.z - b.position.z).abs(), lessThan(1e-6));
        expect((a.velocity.x - b.velocity.x).abs(), lessThan(1e-9));
        expect((a.velocity.y - b.velocity.y).abs(), lessThan(1e-9));
        expect((a.velocity.z - b.velocity.z).abs(), lessThan(1e-9));
      }

      compareAt(epoch);
      compareAt(epoch.add(const Duration(minutes: 360)));
    });

    test('wgs84 produces a different position than wgs72 (default)', () {
      final el = GpElements.fromTle(line1, line2);
      final t = DateTime.utc(2000, 6, 28, 12);
      // Pass wgs72 explicitly (the default) to make the contrast with wgs84
      // self-documenting; the default-equals check below confirms it is live.
      // ignore: avoid_redundant_argument_values
      final wgs72 = Sgp4Engine(el, gravity: GravityModel.wgs72).propagate(t);
      final wgs84 = Sgp4Engine(el, gravity: GravityModel.wgs84).propagate(t);
      // The gravity-model wiring is live: the two models give distinct states.
      expect(wgs84.position, isNot(equals(wgs72.position)));
      // wgs72 is the default.
      final defaultState = Sgp4Engine(el).propagate(t);
      expect(defaultState, equals(wgs72));
    });

    test(
        'FR-4: a reused engine matches a fresh engine per time across a '
        'series', () {
      final times = <DateTime>[
        DateTime.utc(2000, 6, 28, 12),
        DateTime.utc(2000, 6, 28, 13),
        DateTime.utc(2000, 6, 28, 14, 30),
        DateTime.utc(2000, 6, 29),
      ];
      final reused = Sgp4Engine(GpElements.fromTle(line1, line2));
      final series = times.map(reused.propagate).toList();
      final perPoint = times
          .map((t) => Sgp4Engine(GpElements.fromTle(line1, line2)).propagate(t))
          .toList();
      expect(series, equals(perPoint));
    });

    test('a decayed orbit raises PropagationException', () {
      // Catalog 28872 from the Vallado set decays within an hour; propagating
      // well past its lifetime triggers the SGP4 decay error (code 6).
      const decay1 =
          '1 28872U 05037B   05333.02012661  .25992681  00000-0  24476-3 0  1534';
      const decay2 =
          '2 28872  96.4736 157.9986 0303955 244.0492 110.6523 16.46015938 10708';
      final engine = Sgp4Engine(GpElements.fromTle(decay1, decay2));
      // 60 minutes past epoch: the reference stops emitting (decay) at 55 min.
      expect(
        () => engine.propagate(
          engine.epoch.add(const Duration(minutes: 60)),
        ),
        throwsA(
          isA<PropagationException>().having((e) => e.code, 'code', 6),
        ),
      );
    });
  });
}
