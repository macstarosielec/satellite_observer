// ignore_for_file: avoid_print

/// ## Example
///
/// Find all ISS passes over a ground site within a time window, using the
/// default 10 deg minimum elevation (a realistic obstructed-site horizon - see
/// the README and `SatelliteObserver.passes` docs for the rationale). Each pass
/// prints its rise / culmination / set with the peak elevation.
///
/// This example is fully offline: it uses a committed ISS TLE and a fixed
/// multi-day window near the TLE epoch (so SGP4 is accurate and several passes
/// exist).
///
/// Run it with:
///
/// ```sh
/// dart run example/passes.dart
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

  // A fixed window near the TLE epoch. minElevationDeg defaults to 10 deg
  // (ADR-8); pass `minElevationDeg: 0` for the true geometric horizon, or use
  // a HorizonMask preset (HorizonMask.openSky / HorizonMask.obstructed).
  final from = DateTime.utc(2024, 5, 1, 12, 25);
  final to = DateTime.utc(2024, 5, 4, 12, 25);

  final found = iss.passes(from: from, to: to);
  print('${found.length} ISS passes over Warsaw '
      'from ${from.toIso8601String()} to ${to.toIso8601String()} '
      '(minElevation 10 deg)');

  for (final pass in found) {
    print('  ${pass.rise.utc.toIso8601String()} '
        '-> ${pass.set.utc.toIso8601String()}  '
        'peak ${pass.peakElevationDeg.toStringAsFixed(0)} deg at '
        '${pass.culmination.utc.toIso8601String()}');
  }
}
