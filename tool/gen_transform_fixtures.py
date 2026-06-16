"""Generate independent skyfield reference fixtures for satellite_observer P2.

Produces:
  - iss_pass_lookangles.json : a real ISS pass over Warsaw, sampled while
    the satellite is above the horizon, with GEOMETRIC az/el/range/range-rate.
  - gmst_ref.json            : Greenwich mean sidereal time (deg) at several
    UTC instants.

Geometric (no refraction): we do NOT pass temperature/pressure to altaz(),
so skyfield returns the unrefracted topocentric altitude/azimuth.

Skyfield computes the satellite topocentric position via GMST-based
TEME -> ITRF plus polar motion; our Dart omits polar motion, so we expect
arc-second-level agreement.
"""

import datetime
import json
import numpy as np
from skyfield.api import EarthSatellite, load, wgs84

# --- Fixed real ISS (ZARYA) TLE (NORAD 25544). Epoch ~ 2024 day 122. ---
TLE_NAME = "ISS (ZARYA)"
TLE_L1 = "1 25544U 98067A   24122.51736111  .00016717  00000-0  30074-3 0  9991"
TLE_L2 = "2 25544  51.6406 211.0067 0004572  86.8242 273.3318 15.50186571 12345"

# --- Fixed observer: Warsaw ---
OBS_LAT = 52.2297
OBS_LON = 21.0122
OBS_ALT_M = 100.0

ts = load.timescale()
sat = EarthSatellite(TLE_L1, TLE_L2, TLE_NAME, ts)
observer = wgs84.latlon(OBS_LAT, OBS_LON, elevation_m=OBS_ALT_M)

# Search a ~1-day window starting at the TLE epoch for passes, then pick the
# highest-culmination pass so the geometry test exercises a real overhead pass.
t0 = sat.epoch
t1 = ts.tt_jd(t0.tt + 1.0)

times, events = sat.find_events(observer, t0, t1, altitude_degrees=0.0)
# events: 0 = rise (above horizon), 1 = culminate, 2 = set.
diff = sat - observer

best = None  # (peak_el, t_rise, t_set)
i = 0
while i < len(events):
    if events[i] == 0:
        # Find matching set after this rise.
        j = i + 1
        while j < len(events) and events[j] != 2:
            j += 1
        if j < len(events):
            t_r, t_s = times[i], times[j]
            # Peak elevation = highest altitude inside [t_r, t_s].
            peak = max(
                diff.at(ts.tt_jd(t_r.tt + f * (t_s.tt - t_r.tt))).altaz()[0].degrees
                for f in [x / 40.0 for x in range(0, 41)]
            )
            if best is None or peak > best[0]:
                best = (peak, t_r, t_s)
            i = j + 1
            continue
    i += 1

if best is None:
    raise SystemExit("No complete pass found in window")

_, t_rise, t_set = best

# Sample every 20 s strictly inside the pass (elevation > 0).
#
# CRITICAL for fixture/Dart consistency: we sample at WHOLE-SECOND UTC instants
# and build the Skyfield Time from those integer seconds. The stored ISO string
# (utc_iso, second resolution) then represents *exactly* the instant Skyfield
# evaluated, so the Dart engine - which parses that ISO string - propagates at
# the identical instant. (Sampling on a TT grid and storing a rounded ISO would
# introduce a sub-second offset, ~0.2 km of range error at 7 km/s, masking the
# true transform accuracy.)
import math as _m  # noqa: E402

dt_s = 20
# First whole second strictly after rise; last whole second strictly before set.
rise_unix = ts.tt_jd(t_rise.tt).utc_datetime().timestamp()
set_unix = ts.tt_jd(t_set.tt).utc_datetime().timestamp()
start_s = int(_m.ceil(rise_unix))
end_s = int(_m.floor(set_unix))
samples = []
for unix_s in range(start_s, end_s + 1, dt_s):
    dt = datetime.datetime.fromtimestamp(unix_s, tz=datetime.timezone.utc)
    t = ts.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second)
    topo = diff.at(t)
    alt, az, dist = topo.altaz()  # geometric: no refraction
    if alt.degrees <= 0.0:
        continue
    # Range-rate: relative velocity dotted with line-of-sight unit vector.
    r = topo.position.km                  # 3-vector, km
    v = topo.velocity.km_per_s            # 3-vector, km/s
    rmag = np.linalg.norm(r)
    los = r / rmag
    range_rate = float(np.dot(v, los))    # +receding
    samples.append({
        "utc": t.utc_iso(),               # ISO8601 Z
        "azDeg": float(az.degrees),
        "elDeg": float(alt.degrees),
        "rangeKm": float(dist.km),
        "rangeRateKmS": range_rate,
    })

if len(samples) < 5:
    raise SystemExit(f"Too few samples ({len(samples)}); pick a better pass")

lookangles = {
    "tle": {"line1": TLE_L1, "line2": TLE_L2, "name": TLE_NAME},
    "observer": {"latDeg": OBS_LAT, "lonDeg": OBS_LON, "altM": OBS_ALT_M},
    "samples": samples,
}

# --- GMST reference samples (independent: skyfield's t.gmst, hours -> deg) ---
gmst_instants = [
    "2000-01-01T12:00:00Z",   # J2000 epoch
    "2024-05-01T00:00:00Z",
    "2024-05-01T12:34:56Z",
    "2024-12-21T18:00:00Z",
    "2026-06-16T03:21:09Z",
]
# We validate the package's IAU-1982 GMST under its documented UT1 ~= UTC
# simplification. Skyfield's own SGP4/TEME->ITRF path uses the same IAU-1982
# polynomial via theta_GMST1982; feeding it the UTC Julian date (UT1 := UTC)
# is the independent reference for exactly the formula the package implements.
# (t.gmst would instead apply Skyfield's UT1 model, a different convention than
# the package deliberately adopts per ADR-4 / NG5.)
from skyfield.sgp4lib import theta_GMST1982  # noqa: E402

def _jd_utc(y, mo, d, h, mi, s):
    a = (14 - mo) // 12
    yy = y + 4800 - a
    mm = mo + 12 * a - 3
    jdn = d + (153 * mm + 2) // 5 + 365 * yy + yy // 4 - yy // 100 + yy // 400 - 32045
    return jdn - 0.5 + (h * 3600 + mi * 60 + s) / 86400.0

gmst_samples = []
for iso in gmst_instants:
    yr = int(iso[0:4]); mo = int(iso[5:7]); dy = int(iso[8:10])
    hh = int(iso[11:13]); mm = int(iso[14:16]); ss = int(iso[17:19])
    jd = _jd_utc(yr, mo, dy, hh, mm, ss)
    theta, _ = theta_GMST1982(jd, 0.0)     # radians
    gmst_deg = float(np.degrees(theta) % 360.0)
    gmst_samples.append({"utc": iso, "gmstDeg": gmst_deg})

gmst_ref = {"samples": gmst_samples}

import os  # noqa: E402

# Output directory, resolved relative to this script: <repo-root>/tool/.. ->
# <repo-root>/test/fixtures/transforms. Keeps the generator portable when the
# repo is checked out anywhere.
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(_REPO_ROOT, "test", "fixtures", "transforms")
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "iss_pass_lookangles.json"), "w") as f:
    json.dump(lookangles, f, indent=2)
    f.write("\n")
with open(os.path.join(OUT, "gmst_ref.json"), "w") as f:
    json.dump(gmst_ref, f, indent=2)
    f.write("\n")

print("pass samples:", len(samples))
print("first:", samples[0])
print("peak el:", max(s["elDeg"] for s in samples))
print("gmst samples:", len(gmst_samples))
print("skyfield version:", __import__("skyfield").__version__)
