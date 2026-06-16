"""Generate an independent skyfield pass-window reference for satellite_observer P3.

Produces:
  - test/fixtures/passes/iss_passes_window.json : every ISS pass over a fixed
    observer across a multi-day window, found by skyfield's `find_events` at a
    10-deg minimum elevation, with GEOMETRIC (no-refraction) alt/az/range at
    each rise/culmination/set event.

This is the L3 gate (ADR-5 / FR-9). The same fixed TLE + observer + window are
used by test/passes/iss_passes_window_test.dart so the ONLY difference between
this reference and the Dart result is the pass-finding implementation (both run
the same SGP4). skyfield's find_events brackets events on its own internal grid
then refines; our Dart coarse-sample + root-refine should match the event times
to sub-second-ish and the peak elevation to a few hundredths of a degree.

Geometric (no refraction): altaz() is called WITHOUT temperature/pressure, so
skyfield returns the unrefracted topocentric altitude/azimuth - matching the
package, which models no atmospheric refraction (ADR-4 / NG5).
"""

import datetime
import json
import os

import numpy as np
from skyfield.api import EarthSatellite, load, wgs84

# --- Fixed real ISS (ZARYA) TLE (NORAD 25544). Same TLE as the P2 fixture. ---
TLE_NAME = "ISS (ZARYA)"
TLE_L1 = "1 25544U 98067A   24122.51736111  .00016717  00000-0  30074-3 0  9991"
TLE_L2 = "2 25544  51.6406 211.0067 0004572  86.8242 273.3318 15.50186571 12345"

# --- Fixed observer: Warsaw (same as the P2 fixture). ---
OBS_LAT = 52.2297
OBS_LON = 21.0122
OBS_ALT_M = 100.0

# --- Minimum elevation for the pass gate (ADR-8 default). ---
MIN_EL_DEG = 10.0

# --- Window: 3 days starting at the TLE epoch. ---
WINDOW_DAYS = 3.0

ts = load.timescale()
sat = EarthSatellite(TLE_L1, TLE_L2, TLE_NAME, ts)
observer = wgs84.latlon(OBS_LAT, OBS_LON, elevation_m=OBS_ALT_M)
diff = sat - observer

t0 = sat.epoch
t1 = ts.tt_jd(t0.tt + WINDOW_DAYS)

# find_events at the 10-deg threshold: 0 = rise, 1 = culminate, 2 = set.
times, events = sat.find_events(observer, t0, t1, altitude_degrees=MIN_EL_DEG)


def geometric_altaz(t):
    """Return (alt_deg, az_deg, range_km) - geometric, no refraction."""
    topo = diff.at(t)
    alt, az, dist = topo.altaz()  # no temperature/pressure => unrefracted
    return float(alt.degrees), float(az.degrees), float(dist.km)


# Assemble fully-bracketed rise/culminate/set triples. Only complete passes
# (rise, then culminate, then set, all inside the window) are emitted - this
# matches the Dart boundary policy (in-progress passes at either edge skipped).
passes = []
i = 0
n = len(events)
while i < n:
    if events[i] != 0:
        # Not a rise (e.g. a pass already in progress at t0 yields culminate/set
        # without a preceding rise) - skip until the next rise.
        i += 1
        continue
    if i + 2 < n and events[i + 1] == 1 and events[i + 2] == 2:
        t_rise = times[i]
        t_culm = times[i + 1]
        t_set = times[i + 2]

        _, _, _ = geometric_altaz(t_rise)
        peak_alt, _, _ = geometric_altaz(t_culm)

        passes.append({
            "riseUtc": t_rise.utc_iso(),
            "culminationUtc": t_culm.utc_iso(),
            "setUtc": t_set.utc_iso(),
            "peakElevationDeg": peak_alt,
        })
        i += 3
    else:
        # Incomplete triple at this rise (truncated by the window edge) - skip.
        i += 1

if len(passes) < 2:
    raise SystemExit(
        f"Too few complete passes ({len(passes)}); widen the window"
    )

fixture = {
    "tle": {"line1": TLE_L1, "line2": TLE_L2, "name": TLE_NAME},
    "observer": {"latDeg": OBS_LAT, "lonDeg": OBS_LON, "altM": OBS_ALT_M},
    "minElevationDeg": MIN_EL_DEG,
    "window": {"fromUtc": t0.utc_iso(), "toUtc": t1.utc_iso()},
    "passes": passes,
}

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(_REPO_ROOT, "test", "fixtures", "passes")
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "iss_passes_window.json"), "w") as f:
    json.dump(fixture, f, indent=2)
    f.write("\n")

print("complete passes:", len(passes))
for p in passes:
    print(
        "  rise", p["riseUtc"],
        "culm", p["culminationUtc"],
        "set", p["setUtc"],
        "peakEl %.3f" % p["peakElevationDeg"],
    )
print("window:", t0.utc_iso(), "->", t1.utc_iso())
print("skyfield version:", __import__("skyfield").__version__)
print("numpy version:", np.__version__)
