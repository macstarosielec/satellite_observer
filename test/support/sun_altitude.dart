// Test-only bridge to the library-private Sun topocentric-altitude helper.
//
// The visibility calculator's `sunTopocentricAltitudeDeg` is library-private
// (it is part of the internal L4 seam, not the public surface). Tests in this
// same package may import `src/` directly; this thin re-export keeps that
// single internal dependency in one place so the test files read cleanly.

import 'package:satellite_observer/satellite_observer.dart';
import 'package:satellite_observer/src/visibility/visibility_calculator.dart'
    as vis;

/// The Sun's geometric topocentric altitude at [utc] for [observer], in degrees
/// (the package's analytic Meeus value, via the internal calculator).
double sunAltitudeForTest(DateTime utc, Observer observer) =>
    vis.sunTopocentricAltitudeDeg(utc, observer);
