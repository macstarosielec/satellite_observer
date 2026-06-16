"""Generate INDEPENDENT skyfield references for satellite_observer P4 (L4).

Produces two fixtures under test/fixtures/visibility/:

  1. sun_altitude_ref.json
     For a fixed observer and a set of UTC instants spanning day / twilight /
     night, skyfield's Sun GEOMETRIC topocentric altitude (deg). This gates the
     analytic Meeus Sun model (test/solar/sun_position_test.dart).

  2. iss_visibility_ref.json
     For a FIXED ISS TLE + observer: one EVENING pass that is genuinely visible
     (observer in twilight/dark AND satellite sunlit) and one DAYTIME pass (not
     visible). For a fine time grid across each pass, records skyfield's
     `satellite.at(t).is_sunlit(eph)` (boolean) and the Sun topocentric altitude,
     plus the visible sub-interval(s) skyfield derives (alt < -6 deg AND sunlit).
     This gates the eclipse test (test/solar/eclipse_test.dart) and the
     end-to-end visibility gate (test/visibility/iss_visible_pass_test.dart).

REFERENCE ONLY: skyfield uses the JPL DE421 ephemeris (auto-downloaded) for the
Sun and for is_sunlit. The package itself is analytic / ephemeris-free (ADR-2,
NFR-5); de421 is NOT bundled. Geometric altitudes (no atmospheric refraction)
match the package (ADR-6 / NG5).

Run:
    python3 -m venv .venv && .venv/bin/pip install skyfield
    .venv/bin/python tool/gen_visibility_fixtures.py
"""

import json
import os

import numpy as np
from skyfield.api import EarthSatellite, load, wgs84

# --- Fixed real ISS (ZARYA) TLE (NORAD 25544). Same TLE as the P2/P3 fixtures.
TLE_NAME = "ISS (ZARYA)"
TLE_L1 = "1 25544U 98067A   24122.51736111  .00016717  00000-0  30074-3 0  9991"
TLE_L2 = "2 25544  51.6406 211.0067 0004572  86.8242 273.3318 15.50186571 12345"

# --- Fixed observer: Warsaw (same as the P2/P3 fixtures). ---
OBS_LAT = 52.2297
OBS_LON = 21.0122
OBS_ALT_M = 100.0

# --- Twilight gate (ADR-7 default: civil -6 deg). ---
TWILIGHT_DEG = -6.0

# --- Minimum elevation for the pass gate (ADR-8 default). ---
MIN_EL_DEG = 10.0

# --- Search horizon for picking the evening + daytime passes. ---
SEARCH_DAYS = 5.0

# --- Fine grid step across each pass (seconds) for the per-sample comparison.
PASS_GRID_S = 5.0

ts = load.timescale()
eph = load("de421.bsp")
sun = eph["sun"]
earth = eph["earth"]

sat = EarthSatellite(TLE_L1, TLE_L2, TLE_NAME, ts)
topos = wgs84.latlon(OBS_LAT, OBS_LON, elevation_m=OBS_ALT_M)
observer = earth + topos
diff = sat - topos


def sun_alt_deg(t):
    """Geometric topocentric Sun altitude (deg), no refraction."""
    alt, _az, _d = observer.at(t).observe(sun).apparent().altaz()
    return float(alt.degrees)


def sat_alt_deg(t):
    """Geometric topocentric satellite altitude (deg), no refraction."""
    alt, _az, _d = diff.at(t).altaz()
    return float(alt.degrees)


# ---------------------------------------------------------------------------
# Fixture 1: Sun altitude reference across a single day (day/twilight/night).
# ---------------------------------------------------------------------------
# Sample every 20 minutes across 24 h starting at 00:00 UTC on the TLE-epoch
# day, so the set spans full day, both twilights, and deep night.
epoch_dt = sat.epoch.utc_datetime()
day0 = ts.utc(epoch_dt.year, epoch_dt.month, epoch_dt.day, 0, 0, 0)

sun_samples = []
n_steps = int(24 * 60 / 20)  # every 20 min
for k in range(n_steps + 1):
    t = ts.tt_jd(day0.tt + k * (20.0 / 60.0 / 24.0))
    sun_samples.append({
        "utc": t.utc_iso(),
        "sunAltDeg": sun_alt_deg(t),
    })

sun_fixture = {
    "observer": {"latDeg": OBS_LAT, "lonDeg": OBS_LON, "altM": OBS_ALT_M},
    "samples": sun_samples,
}

# ---------------------------------------------------------------------------
# Fixture 2: ISS visibility. Find passes, classify each as evening-visible or
# daytime, then emit one of each with a fine per-sample grid.
# ---------------------------------------------------------------------------
t0 = sat.epoch
t1 = ts.tt_jd(t0.tt + SEARCH_DAYS)
times, events = sat.find_events(topos, t0, t1, altitude_degrees=MIN_EL_DEG)


def build_pass_record(t_rise, t_set):
    """Sample a pass [rise, set] on a fine grid; return the record dict."""
    rise_jd = t_rise.tt
    set_jd = t_set.tt
    span_s = (set_jd - rise_jd) * 86400.0
    n = max(2, int(round(span_s / PASS_GRID_S)))
    samples = []
    # Build the contiguous visible sub-intervals (alt<-6 AND sunlit) directly
    # from the sampled booleans, mirroring the Dart calculator's sampling.
    visible_flags = []
    sample_times = []
    for j in range(n + 1):
        t = ts.tt_jd(rise_jd + (set_jd - rise_jd) * (j / n))
        s_alt = sun_alt_deg(t)
        sunlit = bool(sat.at(t).is_sunlit(eph))
        samples.append({
            "utc": t.utc_iso(),
            "sunlit": sunlit,
            "sunAltDeg": s_alt,
        })
        sample_times.append(t)
        visible_flags.append((s_alt < TWILIGHT_DEG) and sunlit)

    intervals = []
    open_idx = None
    for j, flag in enumerate(visible_flags):
        if flag and open_idx is None:
            open_idx = j
        elif not flag and open_idx is not None:
            intervals.append({
                "startUtc": sample_times[open_idx].utc_iso(),
                "endUtc": sample_times[j - 1].utc_iso(),
            })
            open_idx = None
    if open_idx is not None:
        intervals.append({
            "startUtc": sample_times[open_idx].utc_iso(),
            "endUtc": sample_times[-1].utc_iso(),
        })

    return {
        "window": {"from": t_rise.utc_iso(), "to": t_set.utc_iso()},
        "samples": samples,
        "visibleIntervals": intervals,
    }


# Walk find_events into rise/culm/set triples and classify each pass.
evening_pass = None
daytime_pass = None
i = 0
n_ev = len(events)
while i < n_ev:
    if events[i] != 0:
        i += 1
        continue
    if i + 2 < n_ev and events[i + 1] == 1 and events[i + 2] == 2:
        t_rise = times[i]
        t_culm = times[i + 1]
        t_set = times[i + 2]
        i += 3

        rec = build_pass_record(t_rise, t_set)
        has_visible = len(rec["visibleIntervals"]) > 0
        # "Daytime" = the Sun is up (alt > 0) at culmination and the pass is
        # never visible.
        culm_sun = sun_alt_deg(t_culm)
        if has_visible and evening_pass is None:
            evening_pass = rec
        elif (not has_visible) and culm_sun > 0.0 and daytime_pass is None:
            daytime_pass = rec
        if evening_pass is not None and daytime_pass is not None:
            break
    else:
        i += 1

if evening_pass is None:
    raise SystemExit("No genuinely-visible evening pass found; widen SEARCH_DAYS")
if daytime_pass is None:
    raise SystemExit("No clearly-daytime invisible pass found; widen SEARCH_DAYS")

iss_fixture = {
    "tle": {"line1": TLE_L1, "line2": TLE_L2, "name": TLE_NAME},
    "observer": {"latDeg": OBS_LAT, "lonDeg": OBS_LON, "altM": OBS_ALT_M},
    "twilightDeg": TWILIGHT_DEG,
    "minElevationDeg": MIN_EL_DEG,
    "passes": [evening_pass, daytime_pass],
}

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(_REPO_ROOT, "test", "fixtures", "visibility")
os.makedirs(OUT, exist_ok=True)

with open(os.path.join(OUT, "sun_altitude_ref.json"), "w") as f:
    json.dump(sun_fixture, f, indent=2)
    f.write("\n")
with open(os.path.join(OUT, "iss_visibility_ref.json"), "w") as f:
    json.dump(iss_fixture, f, indent=2)
    f.write("\n")

print("sun_altitude_ref.json: %d samples" % len(sun_samples))
print("iss_visibility_ref.json:")
print("  evening (visible) pass window:",
      evening_pass["window"]["from"], "->", evening_pass["window"]["to"])
print("    visible intervals:", evening_pass["visibleIntervals"])
print("  daytime (invisible) pass window:",
      daytime_pass["window"]["from"], "->", daytime_pass["window"]["to"])
print("skyfield version:", __import__("skyfield").__version__)
print("numpy version:", np.__version__)
print("ephemeris: de421.bsp (reference only, NOT bundled)")
