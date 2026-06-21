# satellite_observer examples

All examples below the headline are fully offline: they use a committed ISS
(ZARYA) TLE and a fixed observer/window near the TLE epoch, so SGP4 is accurate
and a pass exists. Run any of them with `dart run example/<file>.dart`.

| File | What it shows | Network |
|------|---------------|---------|
| [`visible_iss_pass.dart`](visible_iss_pass.dart) | The headline: next naked-eye-visible ISS pass over a site | offline |
| [`look_angle.dart`](look_angle.dart) | Propagate to an instant -> azimuth/elevation/range + sub-point | offline |
| [`live_tracking.dart`](live_tracking.dart) | The live/ticking pattern: build one observer, call it across ticks | offline |
| [`passes.dart`](passes.dart) | All ISS passes over a window at the default 10 deg horizon | offline |
| [`fetch_with_celestrak.dart`](fetch_with_celestrak.dart) | The idiomatic fetch -> propagate handoff via `celestrak` | needs network |

## Headline: the next visible ISS pass

```dart
import 'package:satellite_observer/satellite_observer.dart';

// A committed ISS (ZARYA) TLE (epoch 2024-05-01 UTC). In a live app, fetch a
// fresh TLE - see fetch_with_celestrak.dart.
const issLine1 =
    '1 25544U 98067A   24122.51736111  .00016717  00000-0  30074-3 0  9991';
const issLine2 =
    '2 25544  51.6406 211.0067 0004572  86.8242 273.3318 15.50186571 12345';

void main() {
  final iss = SatelliteObserver(
    elements: GpElements.fromTle(issLine1, issLine2, name: 'ISS (ZARYA)'),
    observer: Observer(
      latitudeDeg: 52.2297,
      longitudeDeg: 21.0122,
      altitudeMeters: 100,
    ),
  );

  // Search forward from a fixed instant near the TLE epoch. nextVisiblePass
  // returns the first pass that is above the horizon AND naked-eye visible
  // (observer in darkness while the satellite is sunlit).
  final visible = iss.nextVisiblePass(after: DateTime.utc(2024, 5, 1, 12));
  if (visible == null) {
    print('No visible ISS pass in the next 48 hours from this site.');
    return;
  }

  final look = visible.visibleIntervals.first.peakLookAngle;
  print('Next visible ISS pass culminates at '
      '${visible.pass.culmination.utc} '
      '(peak ${visible.pass.peakElevationDeg.toStringAsFixed(0)} deg). '
      'Look at az ${look.azimuthDeg.toStringAsFixed(0)} deg, '
      'el ${look.elevationDeg.toStringAsFixed(0)} deg.');
}
```

A *visible* pass is one above the horizon where the observer is in darkness and
the satellite is still catching sunlight. The package is spotter-grade and
inherits TLE staleness - see the [top-level README](../README.md) for the full
accuracy caveat and the rationale for the 10-degree minimum-elevation default.
