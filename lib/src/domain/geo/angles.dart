// Library-private angle helpers.
//
// The library does its trigonometry in radians (ADR-13) and only converts to
// degrees at the public boundary. These small pure helpers centralise the
// conversion and normalisation so the rule lives in exactly one place.

import 'dart:math' as math;

/// Two pi, the full-turn constant in radians.
const double twoPi = 2.0 * math.pi;

/// Degrees-per-radian conversion factor.
const double radToDeg = 180.0 / math.pi;

/// Radians-per-degree conversion factor.
const double degToRad = math.pi / 180.0;

/// Converts [radians] to degrees.
double degrees(double radians) => radians * radToDeg;

/// Converts [deg] to radians.
double radians(double deg) => deg * degToRad;

/// Normalises [angle] (radians) to the range `[0, 2*pi)`.
double normalizeTwoPi(double angle) {
  final m = angle % twoPi;
  return m < 0 ? m + twoPi : m;
}

/// Normalises [angle] (radians) to the range `[-pi, pi)`.
double normalizePi(double angle) {
  final m = (angle + math.pi) % twoPi;
  return (m < 0 ? m + twoPi : m) - math.pi;
}
