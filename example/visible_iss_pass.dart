// ignore_for_file: avoid_print

/// ## Example
///
/// The headline capability: find the next naked-eye-visible ISS pass over a
/// ground site and print its visible sub-arc (when to look, where, and how
/// high).
///
/// This example is fully offline. It uses a committed ISS TLE (the same one
/// the test fixtures use) and a fixed observer near the TLE epoch, so SGP4 is
/// accurate and a visible pass exists. In a real app you would fetch a fresh
/// TLE (see the "Pair with celestrak" section of the README) instead of
/// hard-coding one.
///
/// Run it with:
///
/// ```sh
/// dart run example/visible_iss_pass.dart
/// ```
library;

import 'package:satellite_observer/satellite_observer.dart';

/// A committed ISS (ZARYA) TLE. Epoch is 2024 day 122 (2024-05-01 UTC), so the
/// fixed search window below sits right on the epoch where SGP4 is accurate.
/// This is a synthetic fixture (the revolution number and line-1 checksum are
/// placeholders); `GpElements.fromTle` does not enforce TLE checksums.
const _issLine1 =
    '1 25544U 98067A   24122.51736111  .00016717  00000-0  30074-3 0  9991';
const _issLine2 =
    '2 25544  51.6406 211.0067 0004572  86.8242 273.3318 15.50186571 12345';

void main() {
  // Build the observer/elements pair. The observer here is Warsaw, Poland.
  final iss = SatelliteObserver(
    elements: GpElements.fromTle(_issLine1, _issLine2, name: 'ISS (ZARYA)'),
    observer: Observer(
      latitudeDeg: 52.2297,
      longitudeDeg: 21.0122,
      altitudeMeters: 100,
    ),
  );

  // Search forward from a fixed instant near the TLE epoch. nextVisiblePass
  // scans the window and returns the first pass that is both above the horizon
  // and naked-eye visible (observer in darkness AND satellite sunlit).
  final after = DateTime.utc(2024, 5, 1, 12);
  // `within` defaults to 48 hours; pass it explicitly to widen/narrow.
  final visible = iss.nextVisiblePass(after: after);

  if (visible == null) {
    print('No visible ISS pass in the next 48 hours from this site.');
    return;
  }

  // The underlying geometric pass (rise / culmination / set).
  final pass = visible.pass;
  print('Next visible ISS pass over Warsaw');
  print('  rise        ${pass.rise.utc.toIso8601String()}  '
      'az ${pass.rise.lookAngle.azimuthDeg.toStringAsFixed(0)} deg');
  print('  culmination ${pass.culmination.utc.toIso8601String()}  '
      'el ${pass.peakElevationDeg.toStringAsFixed(0)} deg');
  print('  set         ${pass.set.utc.toIso8601String()}  '
      'az ${pass.set.lookAngle.azimuthDeg.toStringAsFixed(0)} deg');

  // The visible sub-arc(s): when the satellite is actually catching sunlight
  // against a dark-enough sky. This is the part to look up at.
  for (final interval in visible.visibleIntervals) {
    final peak = interval.peakLookAngle;
    print('  visible     ${interval.startUtc.toIso8601String()} '
        '-> ${interval.endUtc.toIso8601String()}');
    print('    look at az ${peak.azimuthDeg.toStringAsFixed(0)} deg, '
        'el ${peak.elevationDeg.toStringAsFixed(0)} deg '
        '(range ${peak.rangeKm.toStringAsFixed(0)} km)');
  }
}
