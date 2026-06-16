import 'dart:math' as math;

/// The Earth gravity model used by the SGP4/SDP4 propagator.
///
/// WGS-72 is the model the canonical SGP4 verification vectors were generated
/// with and is the default; WGS-84 is the more recent geodetic standard.
enum GravityModel {
  /// World Geodetic System 1972 - the SGP4 standard and library default.
  wgs72,

  /// World Geodetic System 1984 - the modern geodetic reference.
  wgs84,
}

/// The set of physical constants for a [GravityModel].
///
/// Ported from `getgravconst` in the MIT-licensed python-sgp4
/// (Brandon Rhodes), itself derived from Vallado, Crawford, Hujsak, Kelso,
/// "Revisiting Spacetrack Report #3", AIAA 2006-6753.
final class GravityConstants {
  const GravityConstants._({
    required this.tumin,
    required this.mu,
    required this.radiusearthkm,
    required this.xke,
    required this.j2,
    required this.j3,
    required this.j4,
    required this.j3oj2,
  });

  /// Minutes in one canonical time unit.
  final double tumin;

  /// Earth gravitational parameter, in km^3 / s^2.
  final double mu;

  /// Earth equatorial radius, in km.
  final double radiusearthkm;

  /// Reciprocal of [tumin] (sqrt(GM) in canonical units).
  final double xke;

  /// Second zonal harmonic coefficient.
  final double j2;

  /// Third zonal harmonic coefficient.
  final double j3;

  /// Fourth zonal harmonic coefficient.
  final double j4;

  /// [j3] divided by [j2].
  final double j3oj2;

  /// Returns the constant set for the given [model].
  static GravityConstants of(GravityModel model) => switch (model) {
        GravityModel.wgs72 => _wgs72,
        GravityModel.wgs84 => _wgs84,
      };

  static final GravityConstants _wgs72 = () {
    const mu = 398600.8;
    const radiusearthkm = 6378.135;
    final xke =
        60.0 / math.sqrt(radiusearthkm * radiusearthkm * radiusearthkm / mu);
    const j2 = 0.001082616;
    const j3 = -0.00000253881;
    const j4 = -0.00000165597;
    return GravityConstants._(
      tumin: 1.0 / xke,
      mu: mu,
      radiusearthkm: radiusearthkm,
      xke: xke,
      j2: j2,
      j3: j3,
      j4: j4,
      j3oj2: j3 / j2,
    );
  }();

  static final GravityConstants _wgs84 = () {
    const mu = 398600.5;
    const radiusearthkm = 6378.137;
    final xke =
        60.0 / math.sqrt(radiusearthkm * radiusearthkm * radiusearthkm / mu);
    const j2 = 0.00108262998905;
    const j3 = -0.00000253215306;
    const j4 = -0.00000161098761;
    return GravityConstants._(
      tumin: 1.0 / xke,
      mu: mu,
      radiusearthkm: radiusearthkm,
      xke: xke,
      j2: j2,
      j3: j3,
      j4: j4,
      j3oj2: j3 / j2,
    );
  }();
}
