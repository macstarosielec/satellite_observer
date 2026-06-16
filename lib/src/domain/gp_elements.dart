import 'dart:math' as math;

import 'package:satellite_observer/src/domain/failures.dart';

const double _deg2rad = math.pi / 180.0;
// xpdotp = 1440.0 / (2 * pi) - revolutions/day <-> radians/minute factor.
const double _xpdotp = 1440.0 / (2.0 * math.pi);

/// A set of general-perturbations mean orbital elements.
///
/// These are the SGP4-ready elements, either parsed from a Two-Line Element
/// set ([GpElements.fromTle]) or supplied directly via
/// [GpElements.fromMeanElements].
///
/// Internally the elements are stored in SGP4 units: angles in radians, mean
/// motion in radians per minute, and the epoch as a UTC [DateTime].
final class GpElements {
  GpElements._({
    required this.epoch,
    required this.name,
    required double inclo,
    required double nodeo,
    required double ecco,
    required double argpo,
    required double mo,
    required double noKozai,
    required double bstar,
    required double ndot,
    required double nddot,
  })  : _inclo = inclo,
        _nodeo = nodeo,
        _ecco = ecco,
        _argpo = argpo,
        _mo = mo,
        _noKozai = noKozai,
        _bstar = bstar,
        _ndot = ndot,
        _nddot = nddot;

  /// Parses a Two-Line Element set.
  ///
  /// [line1] and [line2] are the two 69-column TLE data lines (any trailing
  /// content past column 69, such as the verification start/stop/step fields,
  /// is ignored). [name] is an optional human-readable label.
  ///
  /// Checksums are intentionally not enforced: several canonical verification
  /// TLEs carry deliberately invalid checksums.
  ///
  /// Throws [InvalidElementsException] if a numeric field is malformed or the
  /// resulting elements are non-physical.
  factory GpElements.fromTle(String line1, String line2, {String name = ''}) {
    if (line1.length < 69 || line2.length < 69) {
      throw const InvalidElementsException(
        'TLE lines must be at least 69 characters long',
      );
    }
    final l1 = line1.substring(0, 69);
    final l2 = line2.substring(0, 69);

    try {
      final twoDigitYear = int.parse(l1.substring(18, 20).trim());
      final epochDays = double.parse(l1.substring(20, 32).trim());
      final ndotRaw = _parseSignedDecimal(l1.substring(33, 43));
      final nddotRaw = _parseAssumedDecimal(l1.substring(44, 50));
      final nexp = int.parse(l1.substring(50, 52).trim());
      final bstarRaw = _parseAssumedDecimal(l1.substring(53, 59));
      final ibexp = int.parse(l1.substring(59, 61).trim());

      final inclo = double.parse(l2.substring(8, 16).trim());
      final nodeo = double.parse(l2.substring(17, 25).trim());
      final eccoDigits = l2.substring(26, 33).replaceAll(' ', '0');
      final ecco = double.parse('0.$eccoDigits');
      final argpo = double.parse(l2.substring(34, 42).trim());
      final mo = double.parse(l2.substring(43, 51).trim());
      final noKozaiRevPerDay = double.parse(l2.substring(52, 63).trim());

      final year =
          twoDigitYear < 57 ? twoDigitYear + 2000 : twoDigitYear + 1900;
      final epoch = _epochFromYearDay(year, epochDays);

      // ---- unit conversions (see python-sgp4 io.twoline2rv) ----
      final noKozai = noKozaiRevPerDay / _xpdotp; // rad/min
      final nddot = nddotRaw * math.pow(10.0, nexp).toDouble();
      final bstar = bstarRaw * math.pow(10.0, ibexp).toDouble();
      final ndot = ndotRaw / (_xpdotp * 1440.0);
      final nddotFinal = nddot / (_xpdotp * 1440.0 * 1440.0);

      return GpElements._validated(
        epoch: epoch,
        name: name,
        inclo: inclo * _deg2rad,
        nodeo: nodeo * _deg2rad,
        ecco: ecco,
        argpo: argpo * _deg2rad,
        mo: mo * _deg2rad,
        noKozai: noKozai,
        bstar: bstar,
        ndot: ndot,
        nddot: nddotFinal,
      );
    } on InvalidElementsException {
      rethrow;
    } on FormatException catch (e) {
      throw InvalidElementsException('Malformed TLE field: ${e.message}');
    }
    // RangeError (a subclass of ArgumentError) can be raised by substring /
    // field indexing on a short field; ArgumentError covers any other
    // non-physical parse argument. Both are deliberately mapped to the
    // documented domain failure (ADR-10) so no raw Error escapes fromTle.
    // ignore: avoid_catching_errors
    on RangeError catch (e) {
      throw InvalidElementsException('Malformed TLE field: ${e.message}');
    }
    // ignore: avoid_catching_errors
    on ArgumentError catch (e) {
      throw InvalidElementsException('Malformed TLE field: ${e.message}');
    }
  }

  /// Builds elements from mean orbital elements in conventional units.
  ///
  /// Angles are in degrees, mean motion in revolutions per day. [epoch] must
  /// be a UTC instant. Throws [InvalidElementsException] if any value is
  /// non-physical.
  factory GpElements.fromMeanElements({
    required DateTime epoch,
    required double inclinationDeg,
    required double raanDeg,
    required double eccentricity,
    required double argPerigeeDeg,
    required double meanAnomalyDeg,
    required double meanMotionRevPerDay,
    double bStar = 0.0,
    double meanMotionDotRevPerDay2 = 0.0,
    double meanMotionDdotRevPerDay3 = 0.0,
    String name = '',
  }) {
    return GpElements._validated(
      epoch: epoch.toUtc(),
      name: name,
      inclo: inclinationDeg * _deg2rad,
      nodeo: raanDeg * _deg2rad,
      ecco: eccentricity,
      argpo: argPerigeeDeg * _deg2rad,
      mo: meanAnomalyDeg * _deg2rad,
      noKozai: meanMotionRevPerDay / _xpdotp,
      bstar: bStar,
      ndot: meanMotionDotRevPerDay2 / (_xpdotp * 1440.0),
      nddot: meanMotionDdotRevPerDay3 / (_xpdotp * 1440.0 * 1440.0),
    );
  }

  /// The epoch of the elements, as a UTC instant.
  final DateTime epoch;

  /// An optional human-readable name for the object.
  final String name;

  final double _inclo;
  final double _nodeo;
  final double _ecco;
  final double _argpo;
  final double _mo;
  final double _noKozai;
  final double _bstar;
  final double _ndot;
  final double _nddot;

  /// Inclination, in radians.
  double get inclinationRad => _inclo;

  /// Right ascension of the ascending node, in radians.
  double get raanRad => _nodeo;

  /// Eccentricity (dimensionless).
  double get eccentricity => _ecco;

  /// Argument of perigee, in radians.
  double get argPerigeeRad => _argpo;

  /// Mean anomaly, in radians.
  double get meanAnomalyRad => _mo;

  /// Kozai mean motion, in radians per minute.
  double get meanMotionRadPerMin => _noKozai;

  /// The SGP4 drag term (B*).
  double get bStar => _bstar;

  /// First time derivative of the mean motion, in radians per minute squared.
  double get meanMotionDot => _ndot;

  /// Second time derivative of the mean motion, in radians per minute cubed.
  double get meanMotionDdot => _nddot;

  // Placed with the other private helpers (after the public API) rather than
  // at the top; the public factory constructors are the entry points.
  // ignore: sort_constructors_first
  factory GpElements._validated({
    required DateTime epoch,
    required String name,
    required double inclo,
    required double nodeo,
    required double ecco,
    required double argpo,
    required double mo,
    required double noKozai,
    required double bstar,
    required double ndot,
    required double nddot,
  }) {
    if (!ecco.isFinite || ecco < 0.0 || ecco >= 1.0) {
      throw InvalidElementsException(
        'Eccentricity $ecco is outside the range 0 <= e < 1',
      );
    }
    // Inclination is accepted on [0, pi): exactly pi (180 deg) is rejected
    // because a retrograde-equatorial singularity at i == pi makes several
    // SGP4 trig terms (e.g. sin(i)) degenerate; the half-open bound keeps the
    // propagator's domain well-defined.
    if (!inclo.isFinite || inclo < 0.0 || inclo >= math.pi) {
      throw InvalidElementsException(
        'Inclination ${inclo}rad is outside the range 0 <= i < pi',
      );
    }
    if (!noKozai.isFinite || noKozai <= 0.0) {
      throw InvalidElementsException(
        'Mean motion ${noKozai}rad/min must be positive',
      );
    }
    if (!nodeo.isFinite ||
        !argpo.isFinite ||
        !mo.isFinite ||
        !bstar.isFinite ||
        !ndot.isFinite ||
        !nddot.isFinite) {
      throw const InvalidElementsException('Non-finite orbital element');
    }
    return GpElements._(
      epoch: epoch,
      name: name,
      inclo: inclo,
      nodeo: nodeo,
      ecco: ecco,
      argpo: argpo,
      mo: mo,
      noKozai: noKozai,
      bstar: bstar,
      ndot: ndot,
      nddot: nddot,
    );
  }

  // Parses a field like " .00000016" or "-.00000016" (leading sign optional).
  static double _parseSignedDecimal(String field) {
    final t = field.trim();
    // ignore: prefer_int_literals
    if (t.isEmpty) return 0.0;
    return double.parse(t);
  }

  // Parses a TLE assumed-decimal mantissa field like " 22483-4" -> 0.22483.
  // The leading sign (or space) is the mantissa sign; the digits follow an
  // implicit decimal point. An empty/whitespace field is treated as zero so a
  // short line yields a domain failure rather than a raw RangeError.
  static double _parseAssumedDecimal(String field) {
    final t = field.trim();
    // ignore: prefer_int_literals
    if (t.isEmpty) return 0.0;
    final sign = field[0];
    final digits = field.substring(1);
    return double.parse('$sign.$digits');
  }

  // Builds a UTC DateTime from a 4-digit year and a fractional day-of-year
  // (1.0 = start of Jan 1). Mirrors days2mdhms: seconds = (days - 1) * 86400.
  static DateTime _epochFromYearDay(int year, double epochDays) {
    final micros = ((epochDays - 1.0) * 86400.0 * 1e6).round();
    return DateTime.utc(year).add(Duration(microseconds: micros));
  }
}
