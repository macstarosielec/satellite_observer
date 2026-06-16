import 'dart:convert';
import 'dart:io' show File;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:satellite_observer/src/transforms/topocentric.dart' as topo;
import 'package:test/test.dart';

void main() {
  group('SatelliteObserver facade', () {
    late SatelliteObserver sat;
    late Sgp4Engine engine;
    late Observer observer;
    late GpElements elements;
    late DateTime fromUtc;
    late DateTime toUtc;

    setUpAll(() async {
      final raw = await File(
        'test/fixtures/passes/iss_passes_window.json',
      ).readAsString();
      final fixture = jsonDecode(raw) as Map<String, dynamic>;
      final tle = fixture['tle'] as Map<String, dynamic>;
      final obs = fixture['observer'] as Map<String, dynamic>;
      elements = GpElements.fromTle(
        tle['line1'] as String,
        tle['line2'] as String,
        name: tle['name'] as String,
      );
      observer = Observer(
        latitudeDeg: (obs['latDeg'] as num).toDouble(),
        longitudeDeg: (obs['lonDeg'] as num).toDouble(),
        altitudeMeters: (obs['altM'] as num).toDouble(),
      );
      engine = Sgp4Engine(elements);
      sat = SatelliteObserver(elements: elements, observer: observer);
      final window = fixture['window'] as Map<String, dynamic>;
      fromUtc = DateTime.parse(window['fromUtc'] as String);
      toUtc = DateTime.parse(window['toUtc'] as String);
    });

    test('epoch matches the underlying engine', () {
      expect(sat.epoch.isAtSameMomentAs(engine.epoch), isTrue);
    });

    test('propagate delegates to the engine', () {
      final t = fromUtc.add(const Duration(minutes: 42));
      final fromFacade = sat.propagate(t);
      final fromEngine = engine.propagate(t);
      expect(fromFacade, fromEngine);
    });

    test('lookAngleAt equals the internal topocentric result', () {
      final t = DateTime.parse('2024-05-02T02:41:05Z'); // a culmination instant
      final expected = topo.topocentricLookAngle(engine.propagate(t), observer);
      expect(sat.lookAngleAt(t), expected);
    });

    test('subPointAt equals the internal sub-satellite result', () {
      final t = fromUtc.add(const Duration(hours: 3));
      final expected = topo.subSatellitePoint(engine.propagate(t));
      expect(sat.subPointAt(t), expected);
    });

    test('propagateSeries equals per-point propagate and is endpoint-inclusive',
        () {
      final from = fromUtc;
      final to = fromUtc.add(const Duration(minutes: 5));
      const step = Duration(minutes: 1);
      final series =
          sat.propagateSeries(from: from, to: to, step: step).toList();

      // from, +1, +2, +3, +4, +5 (to). Endpoint included even though it lands
      // on the grid here.
      expect(series.length, 6);
      for (final s in series) {
        expect(s, engine.propagate(s.utc));
      }
      expect(series.first.utc.isAtSameMomentAs(from), isTrue);
      expect(series.last.utc.isAtSameMomentAs(to), isTrue);
    });

    test('propagateSeries includes a non-grid-aligned end endpoint', () {
      final from = fromUtc;
      final to = fromUtc.add(const Duration(seconds: 150)); // 2.5 steps
      const step = Duration(minutes: 1);
      final series =
          sat.propagateSeries(from: from, to: to, step: step).toList();
      // from, +60, +120, then the +150 endpoint.
      expect(series.length, 4);
      expect(series.last.utc.isAtSameMomentAs(to), isTrue);
    });

    test('passes default minElevation is 10 deg', () {
      final defaulted = sat.passes(from: fromUtc, to: toUtc);
      // Explicitly passing 10 must match the default - that equality is the
      // assertion, so the "redundant" value is intentional here.
      final explicit10 = sat.passes(
        from: fromUtc,
        to: toUtc,
        // ignore: avoid_redundant_argument_values
        minElevationDeg: 10,
      );
      expect(defaulted.length, explicit10.length);
      for (var i = 0; i < defaulted.length; i++) {
        expect(defaulted[i], explicit10[i]);
      }
    });

    test('passes normalises a non-UTC window to the same passes (ADR-13)', () {
      // ADR-13: times are normalised on input. A local-time window must yield
      // the same passes (within seconds) as the equivalent UTC window.
      final utcPasses = sat.passes(from: fromUtc, to: toUtc);
      expect(utcPasses, isNotEmpty);

      // Build local-time DateTimes for the SAME instants as the UTC bounds.
      final fromLocal = fromUtc.toLocal();
      final toLocal = toUtc.toLocal();
      expect(fromLocal.isUtc, isFalse);
      expect(fromLocal.isAtSameMomentAs(fromUtc), isTrue);

      final localPasses = sat.passes(from: fromLocal, to: toLocal);

      expect(localPasses.length, utcPasses.length);
      for (var i = 0; i < utcPasses.length; i++) {
        final u = utcPasses[i];
        final l = localPasses[i];
        // Emitted instants must be UTC and coincide to within a second.
        expect(l.rise.utc.isUtc, isTrue);
        expect(
          l.rise.utc.difference(u.rise.utc).inMilliseconds.abs(),
          lessThan(1000),
        );
        expect(
          l.culmination.utc.difference(u.culmination.utc).inMilliseconds.abs(),
          lessThan(1000),
        );
        expect(
          l.set.utc.difference(u.set.utc).inMilliseconds.abs(),
          lessThan(1000),
        );
      }
    });

    test('propagate normalises a non-UTC instant (ADR-13)', () {
      final tUtc = fromUtc.add(const Duration(minutes: 37));
      final tLocal = tUtc.toLocal();
      expect(tLocal.isUtc, isFalse);
      // Same instant via a local-time DateTime yields the same ECI state.
      expect(sat.propagate(tLocal), sat.propagate(tUtc));
    });

    test('nextPass returns the first pass from passes(...)', () {
      final all = sat.passes(from: fromUtc, to: toUtc);
      expect(all, isNotEmpty);
      final next = sat.nextPass(
        after: fromUtc,
        within: toUtc.difference(fromUtc),
      );
      expect(next, isNotNull);
      expect(next, all.first);
    });

    test('nextPass returns null when no pass falls within the horizon', () {
      // A 1-minute window starting at the epoch is far too short for a pass.
      final next = sat.nextPass(
        after: fromUtc,
        within: const Duration(minutes: 1),
      );
      expect(next, isNull);
    });

    test('a supplied engine overrides the default', () {
      final custom = Sgp4Engine(elements);
      final withEngine = SatelliteObserver(
        elements: elements,
        observer: observer,
        engine: custom,
      );
      final t = fromUtc.add(const Duration(minutes: 10));
      expect(withEngine.propagate(t), custom.propagate(t));
    });

    group('argument validation', () {
      test('passes throws when from is not before to', () {
        expect(
          () => sat.passes(from: toUtc, to: fromUtc),
          throwsArgumentError,
        );
        expect(
          () => sat.passes(from: fromUtc, to: fromUtc),
          throwsArgumentError,
        );
      });

      test('passes throws for out-of-range minElevation', () {
        expect(
          () => sat.passes(from: fromUtc, to: toUtc, minElevationDeg: -1),
          throwsArgumentError,
        );
        expect(
          () => sat.passes(from: fromUtc, to: toUtc, minElevationDeg: 90),
          throwsArgumentError,
        );
      });

      test('passes throws for a non-positive sampleStep', () {
        expect(
          () => sat.passes(
            from: fromUtc,
            to: toUtc,
            sampleStep: Duration.zero,
          ),
          throwsArgumentError,
        );
      });

      test('propagateSeries throws for bad window or step', () {
        expect(
          () => sat
              .propagateSeries(
                from: toUtc,
                to: fromUtc,
                step: const Duration(minutes: 1),
              )
              .toList(),
          throwsArgumentError,
        );
        expect(
          () => sat
              .propagateSeries(from: fromUtc, to: toUtc, step: Duration.zero)
              .toList(),
          throwsArgumentError,
        );
      });

      test('nextPass throws for a non-positive window', () {
        expect(
          () => sat.nextPass(after: fromUtc, within: Duration.zero),
          throwsArgumentError,
        );
      });
    });

    test('HorizonMask presets carry the documented angles', () {
      expect(HorizonMask.obstructed.minElevationDeg, 10);
      expect(HorizonMask.openSky.minElevationDeg, 0);
      // Usable as a minElevation source.
      final viaMask = sat.passes(
        from: fromUtc,
        to: toUtc,
        minElevationDeg: HorizonMask.obstructed.minElevationDeg,
      );
      final viaDefault = sat.passes(from: fromUtc, to: toUtc);
      expect(viaMask.length, viaDefault.length);
    });
  });
}
