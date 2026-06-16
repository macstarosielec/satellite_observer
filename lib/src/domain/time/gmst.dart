// Greenwich Mean Sidereal Time (IAU-1982), in radians.

import 'package:satellite_observer/src/domain/geo/angles.dart';

/// The Julian Date of the J2000.0 epoch (2000-01-01 12:00:00 TT).
const double _jdJ2000 = 2451545;

/// Days per Julian century.
const double _daysPerJulianCentury = 36525;

/// Seconds per day.
const double _secondsPerDay = 86400;

/// Returns the Julian Date corresponding to the UTC instant [utc].
///
/// Uses the standard Fliegel-Van Flandern calendar-to-JD algorithm for the
/// whole-day part, plus the fractional day from the time of day. The instant
/// is treated as UT1 (the `UT1 ~= UTC` simplification documented on
/// [greenwichMeanSiderealTime]).
double julianDate(DateTime utc) {
  final t = utc.toUtc();
  final year = t.year;
  final month = t.month;
  final day = t.day;

  // Fliegel-Van Flandern: integer JD at 00:00 UT of the given calendar date.
  final a = ((14 - month) / 12).floor();
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  final jdn = day +
      ((153 * m + 2) / 5).floor() +
      365 * y +
      (y / 4).floor() -
      (y / 100).floor() +
      (y / 400).floor() -
      32045;

  // JDN is the Julian Day Number at noon; subtract 0.5 to get JD at 00:00 UT,
  // then add the fractional day. Microsecond resolution avoids drift.
  final secondsOfDay = t.hour * 3600.0 +
      t.minute * 60.0 +
      t.second +
      t.millisecond / 1000.0 +
      t.microsecond / 1e6;
  return jdn - 0.5 + secondsOfDay / _secondsPerDay;
}

/// Computes Greenwich Mean Sidereal Time for the UTC instant [utc], in radians,
/// normalised to `[0, 2*pi)`.
///
/// This is the IAU-1982 GMST polynomial (Vallado, "Fundamentals of
/// Astrodynamics and Applications"), the conventional pairing for SGP4/TEME and
/// the same formulation Skyfield and sat-spotter use in practice:
///
/// ```text
/// T_UT1 = (JD_UT1 - 2451545.0) / 36525
/// GMST_seconds = 67310.54841
///              + (876600 * 3600 + 8640184.812866) * T_UT1
///              + 0.093104 * T_UT1^2
///              - 6.2e-6  * T_UT1^3
/// ```
///
/// The seconds value (seconds of a sidereal day) is reduced modulo 86400 and
/// scaled to radians (one sidereal day = `2*pi` radians).
///
/// ## The UT1 ~= UTC simplification
///
/// GMST is strictly a function of UT1, not UTC. This implementation feeds the
/// UTC instant directly as UT1. The difference DUT1 = UT1 - UTC is kept below
/// 0.9 s by leap-second scheduling, which corresponds to only a few
/// arc-seconds of Earth rotation - negligible against TLE-staleness error
/// (NFR-2) and far smaller than the model already neglects by omitting
/// nutation and polar motion (EOP omitted per NG5, ADR-4). The
/// Earth-orientation parameters are therefore not consulted.
double greenwichMeanSiderealTime(DateTime utc) {
  final jd = julianDate(utc);
  final tUt1 = (jd - _jdJ2000) / _daysPerJulianCentury;

  // IAU-1982 GMST in seconds of a sidereal day.
  final gmstSeconds = 67310.54841 +
      (876600.0 * 3600.0 + 8640184.812866) * tUt1 +
      0.093104 * tUt1 * tUt1 -
      6.2e-6 * tUt1 * tUt1 * tUt1;

  // Reduce to [0, 86400) seconds, then convert to radians (86400 s = 2*pi).
  var seconds = gmstSeconds % _secondsPerDay;
  if (seconds < 0) {
    seconds += _secondsPerDay;
  }
  final radiansGmst = seconds / _secondsPerDay * twoPi;
  // `seconds` is already reduced to [0, 86400), so `radiansGmst` is already in
  // [0, 2*pi); this final normalize is a defensive guard against any
  // floating-point boundary case that lands exactly on 2*pi.
  return normalizeTwoPi(radiansGmst);
}

/// The Earth's mean rotation rate, in radians per second (IAU-82 / WGS-84).
///
/// Used to add the Earth-rotation term to velocities when rotating from the
/// (quasi-inertial) TEME frame into the rotating ECEF frame.
const double earthRotationRateRadPerSec = 7.292115146706979e-5;
