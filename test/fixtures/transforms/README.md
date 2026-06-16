# Topocentric transform reference fixtures

These fixtures are an **independent reference** for the L2 topocentric geometry
layer (GMST, TEME -> ECEF, geodetic, SEZ az/el/range/range-rate). They were
generated with [Skyfield](https://rhodesmill.org/skyfield/) **version 1.54**,
which is an entirely separate implementation from this package's Dart code.
The only thing the Dart tests share with Skyfield is the **input** (the same
TLE and observer); the reference outputs are computed by Skyfield alone, so a
frame/sidereal-time mismatch in the Dart transforms cannot hide.

## `iss_pass_lookangles.json`

A real ISS (ZARYA, NORAD 25544) pass over Warsaw.

* TLE epoch ~ 2024 day 122; the highest-culmination pass in the day after the
  epoch was selected (peak elevation ~ 77 deg) and sampled every 20 s while the
  satellite is above the horizon (elevation > 0).
* Observer: Warsaw, lat 52.2297 deg N, lon 21.0122 deg E, altitude 100 m
  (WGS-84 geodetic).
* For each sample Skyfield computes, via
  `(sat - observer).at(t).altaz()`:
  * `azDeg`   - geometric azimuth (0 = N, clockwise),
  * `elDeg`   - geometric elevation above the horizon,
  * `rangeKm` - slant range (`.distance()`),
  * `rangeRateKmS` - line-of-sight range rate, `dot(relative_velocity, los)`,
    positive when receding.

**Refraction is OFF.** No temperature/pressure is passed to `altaz()`, so the
elevation is the unrefracted (geometric) altitude, matching the geometric
output the Dart code produces.

The Dart test (`test/transforms/iss_pass_lookangle_test.dart`) builds an
`Sgp4Engine` from the *same* embedded TLE, propagates at each sample's UTC, and
runs its own TEME -> ECEF -> SEZ chain.

### Why arc-second-level agreement, not bit-exact

Skyfield's satellite topocentric path uses GMST-based TEME -> ITRF **plus polar
motion**. This package deliberately omits polar motion / nutation / EOP
(ADR-4, NG5): it rotates TEME -> ECEF about Z by GMST only. Polar motion is at
the ~0.3 arc-second level, so az/el agree to a small fraction of a degree.
The chosen tolerances (and the measured worst case) are documented in the test.

## `gmst_ref.json`

Greenwich **mean** sidereal time in degrees at several UTC instants,
normalised to `[0, 360)`. Used to validate the Dart IAU-1982 GMST
implementation directly.

These samples are computed independently by Skyfield's
`skyfield.sgp4lib.theta_GMST1982(jd_utc, 0.0)` (the IAU-1982 GMST polynomial),
fed the UTC Julian date as UT1. That is exactly the convention this package
documents (UT1 ~= UTC per ADR-4 / NG5) and is the same routine Skyfield's own
SGP4/TEME -> ITRF path uses. (Skyfield's `t.gmst` instead applies Skyfield's
full UT1 model, a different convention, so it is deliberately **not** used
here.) Although Skyfield and this package share the IAU-1982 polynomial, the
reference is still independent: it is Skyfield's own implementation of that
polynomial, not this package's Dart code.

## Regeneration

The generator is committed at `tool/gen_transform_fixtures.py` (excluded from
analysis). It is pure Skyfield + NumPy and embeds the fixed TLE/observer above.
Regenerate both fixtures with:

```sh
pip install skyfield==1.54 numpy
python3 tool/gen_transform_fixtures.py
```

All samples in both fixtures (including the `2026-06-16` GMST sample) are
produced by Skyfield, never by this package's Dart GMST.
