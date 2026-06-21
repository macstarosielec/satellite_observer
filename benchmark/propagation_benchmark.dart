// ignore_for_file: avoid_print

/// Micro-benchmark for the two NFR-6 budgets:
///
///   (a) a single `propagate` + `lookAngleAt` should be well under 1 ms
///       (well under one 60 fps frame of 16.7 ms - the AR/real-time persona);
///   (b) a 7-day single-satellite `passes()` search should be well under
///       ~500 ms (interactive, no perceptible lag).
///
/// It also reports (c) the one-time construction cost of a [SatelliteObserver]
/// (the `Sgp4Engine` `sgp4init`) so the construct-vs-call asymmetry is visible.
/// Construction costs roughly as much as a single propagation, so a live
/// tracker that rebuilds an observer every tick doubles its per-tick work for
/// no benefit (and far more inside a `passes()` search, which propagates many
/// times): build once and reuse across ticks rather than reconstruct per frame.
///
/// This is NOT part of CI. Run it manually and record the numbers (with a
/// machine/date caveat) in the README:
///
/// ```sh
/// dart run benchmark/propagation_benchmark.dart
/// ```
///
/// It uses the same committed ISS TLE the examples use, so it is deterministic
/// and offline.
library;

import 'package:satellite_observer/satellite_observer.dart';

const _issLine1 =
    '1 25544U 98067A   24122.51736111  .00016717  00000-0  30074-3 0  9991';
const _issLine2 =
    '2 25544  51.6406 211.0067 0004572  86.8242 273.3318 15.50186571 12345';

void main() {
  final iss = SatelliteObserver(
    elements: GpElements.fromTle(_issLine1, _issLine2, name: 'ISS (ZARYA)'),
    observer: Observer(
      latitudeDeg: 52.2297,
      longitudeDeg: 21.0122,
      altitudeMeters: 100,
    ),
  );

  // --- (a) single propagate + lookAngleAt ---------------------------------
  final base = DateTime.utc(2024, 5, 2, 2, 41, 5);

  // Warm-up (JIT) - vary the instant so nothing is constant-folded.
  for (var i = 0; i < 50000; i++) {
    iss.lookAngleAt(base.add(Duration(seconds: i)));
  }

  const iterations = 200000;
  final swSingle = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    iss.lookAngleAt(base.add(Duration(seconds: i)));
  }
  swSingle.stop();
  final perCallUs = swSingle.elapsedMicroseconds / iterations;
  print('(a) single propagate + lookAngleAt over $iterations iterations:');
  print('    ${perCallUs.toStringAsFixed(3)} us/call '
      '(${(perCallUs / 1000).toStringAsFixed(5)} ms/call)');
  print('    budget: < 1 ms  -> '
      '${perCallUs / 1000 < 1.0 ? 'PASS' : 'EXCEEDED (consider Isolate.run)'}');
  print('');

  // --- (b) 7-day passes() search ------------------------------------------
  final from = DateTime.utc(2024, 5, 1, 12);
  final to = from.add(const Duration(days: 7));

  // Warm-up.
  iss.passes(from: from, to: to);

  const searchRuns = 20;
  final swSearch = Stopwatch()..start();
  var passCount = 0;
  for (var i = 0; i < searchRuns; i++) {
    passCount = iss.passes(from: from, to: to).length;
  }
  swSearch.stop();
  final perSearchMs = swSearch.elapsedMicroseconds / searchRuns / 1000.0;
  print('(b) 7-day passes() search ($passCount passes found), '
      'averaged over $searchRuns runs:');
  print('    ${perSearchMs.toStringAsFixed(2)} ms/search');
  print('    budget: < ~500 ms  -> '
      '${perSearchMs < 500.0 ? 'PASS' : 'EXCEEDED (consider Isolate.run)'}');
  print('');

  // --- (c) one-time construction cost (sgp4init) --------------------------
  // Parse the elements once so we measure the propagator initialisation, not
  // TLE parsing: this is the per-satellite setup that a reuse-minded caller
  // pays once and a per-frame caller pays every tick.
  final elements =
      GpElements.fromTle(_issLine1, _issLine2, name: 'ISS (ZARYA)');
  final observer = Observer(
    latitudeDeg: 52.2297,
    longitudeDeg: 21.0122,
    altitudeMeters: 100,
  );

  // Warm-up (JIT). Propagate each fresh instance once so the constructor's
  // sgp4init cannot be dead-code-eliminated.
  final at = DateTime.utc(2024, 5, 2, 2, 41, 5);
  var sink = 0.0;
  for (var i = 0; i < 5000; i++) {
    sink += SatelliteObserver(elements: elements, observer: observer)
        .lookAngleAt(at)
        .elevationDeg;
  }

  const constructRuns = 50000;
  final swConstruct = Stopwatch()..start();
  for (var i = 0; i < constructRuns; i++) {
    sink += SatelliteObserver(elements: elements, observer: observer)
        .lookAngleAt(at)
        .elevationDeg;
  }
  swConstruct.stop();
  if (sink.isNaN) print(''); // Keep `sink` live.
  // Each iteration is one construction plus one lookAngleAt; subtract the
  // measured single-call cost (a) to isolate the construction (sgp4init).
  final perIterUs = swConstruct.elapsedMicroseconds / constructRuns;
  final perConstructUs = perIterUs - perCallUs;
  print('(c) SatelliteObserver construction (sgp4init) over '
      '$constructRuns iterations:');
  print('    ${perConstructUs.toStringAsFixed(3)} us/construction '
      '(${(perConstructUs / 1000).toStringAsFixed(5)} ms/construction)');
  print('    vs (a): construction is roughly '
      '${(perConstructUs / perCallUs).toStringAsFixed(0)}x a single '
      'propagate + lookAngleAt; build once and reuse across ticks.');
}
