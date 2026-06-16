# satellite_observer

Pure-Dart engine for SGP4 satellite propagation, topocentric look-angles, pass
prediction, and naked-eye visibility. No Flutter dependency; runs on the Dart
VM, Flutter (mobile/desktop), and web.

> Status: early development (v0.1.0 scaffold). The public API is not yet
> available - see the planned capability layers below.

## What it does (planned v1)

- L1 - SGP4 propagation of TLE/OMM elements to an ECI (TEME) state.
- L2 - Topocentric look-angles (azimuth, elevation, range, range-rate) for an
  observer.
- L3 - Pass prediction (rise / culmination / set) over a time window.
- L4 - Visibility: observer twilight darkness AND satellite sunlit/eclipse, via
  an analytic Sun model and a geometric shadow test.

## The stack

`satellite_observer` is the compute layer (Package B) of a Dart satellite stack.
It consumes generic GP elements, so it is usable on its own; it pairs
idiomatically with [`celestrak`](https://pub.dev/packages/celestrak) (Package A,
the data layer) via a "fetch -> propagate" handoff joined on NORAD ID. The
package never merges the two: the data and compute contracts stay separate.

## Accuracy

Spotter-grade, analytic, fully offline. SGP4 correctness is verified against the
canonical Vallado verification vectors. Overall accuracy is dominated by and
inherits TLE staleness - multi-day-old elements degrade results regardless of
the propagator.

## License

MIT. The SGP4/SDP4 implementation is a port of the public-domain Vallado
reference ("Revisiting Spacetrack Report #3", Vallado et al.); attribution is
retained in-source.
