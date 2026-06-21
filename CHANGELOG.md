# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-06-21

Documentation only. No public API or behaviour change.

### Changed

- Clarified that a `SatelliteObserver` (and its `Sgp4Engine`) should be
  constructed once per satellite and reused across ticks, not rebuilt per
  frame. Added a construction-cost row to the Performance table, a "Construct
  once, reuse across ticks" section to the README and the `SatelliteObserver`
  dartdoc, an `example/live_tracking.dart` build-once-then-loop sample, and a
  note that the `engine:` parameter lets one initialised propagator serve
  multiple observers.

## [1.0.0] - 2026-06-16

First stable release: the complete L1-L4 compute set with a frozen public API
(semver-stable from here).

### Added

- **`SatelliteObserver` facade** - the single public entry point. Construct it
  from generic `GpElements` plus an `Observer`; no `celestrak` (or any data
  source) dependency, so it is usable standalone.
- **L1 - SGP4/SDP4 propagation.** Near-Earth and deep-space propagation behind
  the `PropagationEngine` seam (`Sgp4Engine`), verified against the canonical
  Vallado reference vectors (`SGP4-VER.TLE` / `tcppver.out`). `GpElements`
  (from a raw TLE pair via `GpElements.fromTle`, or from mean elements),
  `EciState` (TEME position/velocity), `Vector3`, `GravityModel` (WGS-72
  default, the SGP4 convention). Methods: `propagate`, `propagateSeries`,
  `epoch`.
- **L2 - topocentric geometry.** `lookAngleAt` returns a `LookAngle` (azimuth,
  elevation, slant range, range-rate); `subPointAt` returns a
  `SubSatellitePoint`. WGS-84 geodesy, TEME -> ECEF via IAU-82 GMST.
- **L3 - pass prediction.** `passes` finds rise / culmination / set `Pass`
  triples over a window (coarse sample + root refine), with per-event
  `LookAngle` and peak elevation; `nextPass` is forward-scan sugar.
  `minElevationDeg` defaults to 10 deg (documented), with `HorizonMask`
  presets (`openSky` 0 deg, `obstructed` 10 deg).
- **L4 - naked-eye visibility.** `visiblePasses` / `nextVisiblePass` mark the
  sub-arcs where the observer is in darkness AND the satellite is sunlit,
  returning `PassVisibility` with `VisibleInterval`s. `isObserverInDarkness`
  (with `TwilightPhase` civil/nautical/astronomical or a raw Sun-altitude
  threshold) and `isSatelliteSunlit`. Analytic Meeus Sun model (~arc-minute,
  no ephemeris/network) and a geometric conical-umbra eclipse test.
- **Error model.** Sealed `SatelliteObserverException` tree
  (`InvalidElementsException`, `PropagationException`, `GeometryException`);
  internal failures are mapped so no raw numeric/format error leaks out.
- **Docs & examples.** Visibility-first README with the accuracy/TLE-staleness
  caveat and the 10-degree default rationale; runnable offline examples
  (`visible_iss_pass`, `look_angle`, `passes`) plus a network `celestrak`
  fetch -> propagate example; a propagation benchmark.
- **Tooling.** Strict analysis options (very_good_analysis + strict language
  modes), MIT license with Vallado attribution, and CI (format / analyze /
  test with coverage / publish dry-run).

[1.0.0]: https://github.com/macstarosielec/satellite_observer/releases/tag/v1.0.0
