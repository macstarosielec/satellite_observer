// ignore_for_file: avoid_print

/// ## Example
///
/// Propagate a satellite to a fixed instant and print the topocentric
/// look-angle (azimuth, elevation, slant range, range-rate) and the
/// sub-satellite point.
///
/// This example is fully offline: it uses a committed ISS TLE and a fixed
/// instant near the TLE epoch (so SGP4 is accurate). In a real app you would
/// pass `DateTime.now().toUtc()` and a freshly fetched TLE.
///
/// Run it with:
///
/// ```sh
/// dart run example/look_angle.dart
/// ```
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

  // A fixed instant during a known ISS pass over Warsaw (use
  // DateTime.now().toUtc() in a live app).
  final at = DateTime.utc(2024, 5, 2, 2, 41, 5);

  final look = iss.lookAngleAt(at);
  print('Look-angle at ${at.toIso8601String()}');
  print('  azimuth    ${look.azimuthDeg.toStringAsFixed(1)} deg');
  print('  elevation  ${look.elevationDeg.toStringAsFixed(1)} deg');
  print('  range      ${look.rangeKm.toStringAsFixed(1)} km');
  print('  range-rate ${look.rangeRateKmS.toStringAsFixed(3)} km/s '
      '(${look.rangeRateKmS >= 0 ? 'receding' : 'approaching'})');

  final sub = iss.subPointAt(at);
  print('Sub-satellite point');
  print('  lat ${sub.latitudeDeg.toStringAsFixed(2)} deg, '
      'lon ${sub.longitudeDeg.toStringAsFixed(2)} deg, '
      'alt ${sub.altitudeKm.toStringAsFixed(0)} km');
}
