// ignore_for_file: avoid_print

/// ## Example
///
/// The idiomatic data -> compute handoff: fetch a fresh TLE with the
/// `celestrak` package, then propagate and predict with `satellite_observer`.
///
/// NETWORK REQUIRED. This example performs a live HTTP fetch from CelesTrak and
/// is therefore NOT part of the offline smoke test (other examples are).
/// It is kept compiling under `dart analyze` to document the handoff.
///
/// `celestrak` is a dev_dependency of this package, used only by `example/`.
/// `satellite_observer` itself has NO dependency on `celestrak` (ADR-3): it
/// accepts generic GP elements, so it is usable standalone.
///
/// Run it with (needs network):
///
/// ```sh
/// dart run example/fetch_with_celestrak.dart
/// ```
library;

import 'dart:io' show Directory;

import 'package:celestrak/celestrak.dart';
import 'package:satellite_observer/satellite_observer.dart';

Future<void> main() async {
  final client = CelestrakClient(cacheDir: Directory.systemTemp.path);
  try {
    // 1. Fetch fresh orbital data (data side).
    final tle = await client.fetchByNoradId(25544);
    if (client.isStale(tle)) {
      print('Warning: TLE is stale; propagated results will be degraded.');
    }

    // 2. Hand the raw TLE pair to the compute side.
    final iss = SatelliteObserver(
      elements: GpElements.fromTle(tle.line1, tle.line2, name: tle.name),
      observer: Observer(
        latitudeDeg: 52.2297,
        longitudeDeg: 21.0122,
        altitudeMeters: 100,
      ),
    );

    // 3. Predict the next visible pass from now.
    final visible = iss.nextVisiblePass(after: DateTime.now().toUtc());
    if (visible == null) {
      print('No visible ISS pass in the next 48 hours.');
      return;
    }
    final peak = visible.visibleIntervals.first.peakLookAngle;
    print('Next visible ISS pass culminates at '
        '${visible.pass.culmination.utc.toIso8601String()} '
        '(peak ${visible.pass.peakElevationDeg.toStringAsFixed(0)} deg; '
        'look az ${peak.azimuthDeg.toStringAsFixed(0)} deg, '
        'el ${peak.elevationDeg.toStringAsFixed(0)} deg).');
  } finally {
    client.dispose();
  }
}
