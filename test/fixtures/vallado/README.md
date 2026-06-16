# Vallado SGP4 verification fixtures

This directory holds the canonical SGP4/SDP4 verification vectors:

- `SGP4-VER.TLE` - the verification Two-Line Element sets, each annotated with a
  start/stop/step (minutes) span past column 69.
- `tcppver.out` - the reference position/velocity output for those element sets,
  one block per satellite.

## Source and citation

These fixtures accompany:

> Vallado, Crawford, Hujsak, Kelso, "Revisiting Spacetrack Report #3",
> AIAA 2006-6753.

They are the standard verification data distributed via CelesTrak alongside the
report's reference implementation. The copies here were obtained from the
MIT-licensed python-sgp4 package (Brandon Rhodes), which mirrors them for its
own test suite.

The vectors are reference verification data published with the report
(public-domain / citation-requested). They are used here unmodified, solely to
prove the propagation engine matches the canonical results.
