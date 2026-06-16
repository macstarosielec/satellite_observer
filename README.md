# satellite_observer

A pure-Dart engine for **SGP4/SDP4 satellite propagation**, topocentric
**look-angles**, **pass prediction**, and **naked-eye visibility**.

No Flutter dependency - works on the Dart VM, servers, web/WASM, and Flutter
alike. It is the compute peer of the [celestrak](https://pub.dev/packages/celestrak)
data package: celestrak fetches the orbital elements, satellite_observer turns
them into where-to-look answers.

---

## When is the next visible ISS pass?

That is the headline question this package answers in two lines: feed it
orbital elements and an observer, ask for the next visible pass.

```dart
import 'package:satellite_observer/satellite_observer.dart';

// Your satellite's current TLE (fetch a fresh one - see "Pair with celestrak"
// below). This committed ISS TLE has a 2024-05-01 epoch, so the search is
// anchored near it; in production use a fresh TLE and DateTime.now().
const line1 =
    '1 25544U 98067A   24122.51736111  .00016717  00000-0  30074-3 0  9991';
const line2 =
    '2 25544  51.6406 211.0067 0004572  86.8242 273.3318 15.50186571 12345';

void main() {
  final iss = SatelliteObserver(
    elements: GpElements.fromTle(line1, line2, name: 'ISS (ZARYA)'),
    observer: Observer(latitudeDeg: 52.2297, longitudeDeg: 21.0122),
  );

  final visible = iss.nextVisiblePass(after: DateTime.utc(2024, 5, 1, 12));
  if (visible == null) {
    print('No visible pass in the next 48 hours.');
    return;
  }
  final look = visible.visibleIntervals.first.peakLookAngle;
  print('Look up at ${visible.pass.culmination.utc} - '
      'az ${look.azimuthDeg.toStringAsFixed(0)} deg, '
      'el ${look.elevationDeg.toStringAsFixed(0)} deg.');
}
```

A *visible* pass is one that is above the horizon **and** naked-eye visible:
the observer is in darkness while the satellite is still catching sunlight.
`nextVisiblePass` returns the first such pass, with its visible sub-arc(s) and
the brightest look-angle inside each. See
[`example/visible_iss_pass.dart`](example/visible_iss_pass.dart) for a complete
offline runnable program.

---

## Accuracy (read this first)

This package is **spotter-grade**, not survey-grade. Be honest with your users
about what that means:

- **SGP4/SDP4 is verified against the canonical Vallado reference vectors**
  (`SGP4-VER.TLE` / `tcppver.out`) - the published correctness oracle. The
  propagator itself is not the limiting factor.
- **Results inherit TLE staleness.** Orbital elements age quickly: a multi-day-old
  TLE can place a satellite kilometres from its true position **regardless of how
  good the propagator is**. Always propagate from fresh elements, and warn or
  refresh when they are stale (celestrak's `isStale` helps).
- **The Sun model is analytic Meeus low-precision** (`~arc-minute`), with no
  ephemeris and no network. That is far more than enough for a twilight gate
  (a fraction of a degree on a -6 deg threshold is invisible) and for the
  eclipse/umbra test, but it is **not survey-grade astrometry**.
- The eclipse test is a geometric conical-umbra model and ignores atmospheric
  refraction; look-angles are geometric (no refraction).

For naked-eye spotting, ground-station scheduling, AR overlays, and education
this is the right accuracy class. For precise orbit determination it is not.

---

## The 10-degree minimum-elevation default

Pass and visibility searches default to a **minimum elevation of 10 degrees**
(`minElevationDeg: 10`). This is a realistic obstructed-site horizon, so the
passes you get out of the box are plausibly observable rather than
horizon-hugging behind trees and buildings.

It is **fully overridable**:

```dart
iss.passes(from: a, to: b, minElevationDeg: 0);   // true geometric horizon
iss.passes(from: a, to: b, minElevationDeg: 20);  // hilly / obstructed site
```

There are also self-documenting `HorizonMask` presets
(`HorizonMask.openSky` = 0 deg, `HorizonMask.obstructed` = 10 deg). Passes
below the threshold are filtered out - this is stated here and in the API docs
so a filtered sub-10-degree pass never surprises you.

---

## Installation

```yaml
dependencies:
  satellite_observer: ^1.0.0
```

```dart
import 'package:satellite_observer/satellite_observer.dart';
```

---

## The toolkit

`SatelliteObserver` is the single facade. Construct it from generic
`GpElements` plus an `Observer`, then call:

| Layer | Methods | What you get |
|-------|---------|--------------|
| L1 propagation | `propagate`, `propagateSeries`, `epoch` | `EciState` (TEME position/velocity) |
| L2 geometry | `lookAngleAt`, `subPointAt` | `LookAngle` (az/el/range/range-rate), `SubSatellitePoint` |
| L3 passes | `passes`, `nextPass` | `Pass` (rise / culmination / set + peak elevation) |
| L4 visibility | `visiblePasses`, `nextVisiblePass`, `isObserverInDarkness`, `isSatelliteSunlit` | `PassVisibility` (visible sub-arcs) |

### Propagate to a look-angle

```dart
final look = iss.lookAngleAt(DateTime.now().toUtc());
print('az ${look.azimuthDeg}, el ${look.elevationDeg}, '
    'range ${look.rangeKm} km, range-rate ${look.rangeRateKmS} km/s');
```

See [`example/look_angle.dart`](example/look_angle.dart).

### Find passes over a window

```dart
final now = DateTime.now().toUtc();
final found = iss.passes(
  from: now,
  to: now.add(const Duration(days: 3)),
); // minElevationDeg defaults to 10
for (final pass in found) {
  print('${pass.rise.utc} -> ${pass.set.utc}, '
      'peak ${pass.peakElevationDeg} deg');
}
```

See [`example/passes.dart`](example/passes.dart).

All public methods map internal failures to the sealed
`SatelliteObserverException` tree (`InvalidElementsException`,
`PropagationException`, `GeometryException`); no raw numeric or format error
leaks out. Angles are degrees at the API boundary and all instants are UTC.

---

## Pair with celestrak (fetch -> propagate)

satellite_observer takes **generic** GP-element input, so it is usable
standalone. The idiomatic way to get fresh elements is the sibling
[celestrak](https://pub.dev/packages/celestrak) package. The handoff is the raw
TLE pair:

```dart
// `celestrakClient` is a celestrak CelestrakClient; `me` is your Observer.
// See example/fetch_with_celestrak.dart for the complete program.
final tle = await celestrakClient.fetchByNoradId(25544); // ISS
final obs = SatelliteObserver(
  elements: GpElements.fromTle(tle.line1, tle.line2, name: tle.name),
  observer: me,
);
final next = obs.nextVisiblePass(after: DateTime.now().toUtc());
```

That is the entire data -> compute boundary. **celestrak is NOT a dependency of
this package** - it is a `dev_dependency` used only by the examples
(see [`example/fetch_with_celestrak.dart`](example/fetch_with_celestrak.dart),
which needs network). The core stays celestrak-free so consumers who already
have orbital elements (ground stations, education, custom data sources) need
not adopt it.

---

## Performance

Measured on an Apple Silicon (M-series) Mac, Dart 3.12.0, 2026-06-16
(`dart run benchmark/propagation_benchmark.dart`). Numbers are machine- and
date-dependent; treat them as order-of-magnitude:

| Operation | Budget (NFR-6) | Measured |
|-----------|----------------|----------|
| single `propagate` + `lookAngleAt` | < 1 ms (< one 60 fps frame) | **~0.0006 ms** |
| 7-day single-satellite `passes()` search | < ~500 ms (interactive) | **~14 ms** |

Both budgets are met with a wide margin, so no `Isolate.run` offload is needed;
heavy batch work can still be moved to an isolate by the caller if desired.

---

## Platform support

Pure Dart with no `dart:io` in the core, so it runs everywhere Dart does:
Dart VM, Android, iOS, macOS, Linux, Windows, and web/WASM. Sound null safety
throughout.

---

## License

MIT. The SGP4/SDP4 implementation is an independent Dart port of the public
reference algorithm by Vallado et al. ("Revisiting Spacetrack Report #3",
AIAA 2006-6753) and is verified against the canonical `SGP4-VER` test vectors.
See [LICENSE](LICENSE) for the full text and attribution.
