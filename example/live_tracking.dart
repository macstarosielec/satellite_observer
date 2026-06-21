// ignore_for_file: avoid_print

/// ## Example
///
/// The live / ticking pattern: build a [SatelliteObserver] **once** for a
/// satellite, then call `lookAngleAt` on it in a loop as time advances - the
/// shape a real-time tracker (an AR overlay, a dish pointer, a "where is it
/// now" widget) uses every frame.
///
/// The point of this example is the reuse: construction runs `sgp4init` once,
/// and every tick below reuses that same initialised observer. Do **not**
/// rebuild a fresh `SatelliteObserver` (or `Sgp4Engine`) per tick - that
/// re-pays the SGP4 setup on every frame for no benefit. When one initialised
/// propagator must serve several observers, build the `Sgp4Engine` once and
/// pass it via `SatelliteObserver(engine: ...)`.
///
/// This example is fully offline: it uses a committed ISS TLE and walks a fixed
/// instant near the TLE epoch in 10-second steps (so SGP4 is accurate and the
/// satellite is above the horizon). In a live app the loop would be driven by a
/// timer / frame callback and read `DateTime.now().toUtc()` each tick.
///
/// Run it with:
///
/// ```sh
/// dart run example/live_tracking.dart
/// ```
library;

import 'package:satellite_observer/satellite_observer.dart';

const _issLine1 =
    '1 25544U 98067A   24122.51736111  .00016717  00000-0  30074-3 0  9991';
const _issLine2 =
    '2 25544  51.6406 211.0067 0004572  86.8242 273.3318 15.50186571 12345';

void main() {
  // Construct ONCE, before the loop. This runs sgp4init a single time.
  final iss = SatelliteObserver(
    elements: GpElements.fromTle(_issLine1, _issLine2, name: 'ISS (ZARYA)'),
    observer: Observer(
      latitudeDeg: 52.2297,
      longitudeDeg: 21.0122,
      altitudeMeters: 100,
    ),
  );

  // Simulate a ticking clock during a known ISS pass over Warsaw. In a live app
  // this would be a Timer.periodic / frame callback reading DateTime.now().
  var tick = DateTime.utc(2024, 5, 2, 2, 41, 5);
  const step = Duration(seconds: 10);

  print('Live look-angle (reusing one SatelliteObserver across ticks):');
  for (var i = 0; i < 6; i++) {
    // Reuse `iss` every tick - no reconstruction, no repeated sgp4init.
    final look = iss.lookAngleAt(tick);
    print('  ${tick.toIso8601String()}  '
        'az ${look.azimuthDeg.toStringAsFixed(1)} deg  '
        'el ${look.elevationDeg.toStringAsFixed(1)} deg  '
        'range ${look.rangeKm.toStringAsFixed(0)} km');
    tick = tick.add(step);
  }
}
