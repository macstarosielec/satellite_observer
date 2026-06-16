import 'package:meta/meta.dart';
import 'package:satellite_observer/src/domain/eci_state.dart';
import 'package:satellite_observer/src/domain/failures.dart';
import 'package:satellite_observer/src/domain/gp_elements.dart';
import 'package:satellite_observer/src/propagation/propagation_engine.dart';
import 'package:satellite_observer/src/propagation/sgp4/gravity_constants.dart';
import 'package:satellite_observer/src/propagation/sgp4/sgp4_core.dart';
import 'package:satellite_observer/src/propagation/sgp4/sgp4_init.dart';
import 'package:satellite_observer/src/propagation/sgp4/sgp4_satellite.dart';

/// SGP4/SDP4 propagation engine.
///
/// Initialises the propagator once from a [GpElements] set and then computes
/// the satellite state at arbitrary times. Near-earth orbits use SGP4 and
/// deep-space orbits (period >= 225 minutes) use the SDP4 extensions; the path
/// is selected automatically during initialisation.
///
/// State is returned in the TEME frame (km, km/s).
final class Sgp4Engine implements PropagationEngine {
  /// Creates an engine for [elements] using the given gravity [gravity] model.
  ///
  /// Initialisation runs once here. WGS-72 is the default, matching the
  /// canonical SGP4 verification vectors.
  Sgp4Engine(GpElements elements, {GravityModel gravity = GravityModel.wgs72})
      // Normalise the stored epoch to UTC defensively: a non-UTC epoch would
      // otherwise produce a wrong tsince in propagate.
      : _epoch = elements.epoch.toUtc() {
    final s = Sgp4Satellite(GravityConstants.of(gravity))
      ..operationmode = 'i'
      ..bstar = elements.bStar
      ..ndot = elements.meanMotionDot
      ..nddot = elements.meanMotionDdot
      ..ecco = elements.eccentricity
      ..argpo = elements.argPerigeeRad
      ..inclo = elements.inclinationRad
      ..mo = elements.meanAnomalyRad
      ..noKozai = elements.meanMotionRadPerMin
      ..nodeo = elements.raanRad;

    final epoch1950 = _epochDays1950(elements.epoch);
    s.epochDays1950 = epoch1950;
    sgp4init(s, epoch: epoch1950);
    _satellite = s;
  }

  final DateTime _epoch;
  late final Sgp4Satellite _satellite;

  @override
  DateTime get epoch => _epoch;

  /// Propagates the orbit to [utc] and returns the TEME-frame state.
  ///
  /// A non-UTC DateTime is normalised to UTC; pass UTC to avoid surprises.
  @override
  EciState propagate(DateTime utc) {
    final tsinceMinutes = utc.toUtc().difference(_epoch).inMicroseconds / 6.0e7;
    final result = _propagateTsince(tsinceMinutes);
    return EciState(
      position: result.position,
      velocity: result.velocity,
      utc: utc.toUtc(),
    );
  }

  // Internal test seam: propagate at a raw tsince in minutes (mirrors
  // python-sgp4's sgp4_tsince), avoiding DateTime conversion error in the
  // Vallado verification gate.
  Sgp4Result _propagateTsince(double tsinceMinutes) {
    final result = sgp4Step(_satellite, tsinceMinutes);
    if (result.error != 0) {
      throw PropagationException(
        result.error,
        'SGP4 propagation failed at tsince=$tsinceMinutes min',
      );
    }
    if (!result.position.x.isFinite ||
        !result.position.y.isFinite ||
        !result.position.z.isFinite ||
        !result.velocity.x.isFinite ||
        !result.velocity.y.isFinite ||
        !result.velocity.z.isFinite) {
      // SGP4 reported success but produced NaN/Inf; raise the non-Vallado
      // sentinel code so callers can distinguish it from codes 1..6.
      throw const PropagationException(
        PropagationException.nonFiniteOutputCode,
        'SGP4 produced a non-finite position or velocity',
      );
    }
    return result;
  }

  // Days from 1950 Jan 0.0 for the given UTC epoch, via the Vallado jday
  // formula minus 2433281.5 (matches python-sgp4's sgp4init epoch argument).
  static double _epochDays1950(DateTime epoch) {
    final e = epoch.toUtc();
    final year = e.year;
    final mon = e.month;
    final day = e.day;
    final secOfDay = e.hour * 3600.0 +
        e.minute * 60.0 +
        e.second +
        e.millisecond / 1.0e3 +
        e.microsecond / 1.0e6;
    final jd = 367.0 * year -
        ((7 * (year + ((mon + 9) ~/ 12))) ~/ 4) +
        ((275 * mon) ~/ 9) +
        day +
        1721013.5 +
        secOfDay / 86400.0;
    return jd - 2433281.5;
  }
}

/// Test-only access to the internal raw-tsince propagation seam.
///
/// Used by the Vallado verification gate to feed tsince (minutes) directly,
/// matching python-sgp4's `sgp4_tsince`. Not part of the supported public API.
@visibleForTesting
Sgp4Result propagateTsinceForTesting(Sgp4Engine engine, double tsinceMinutes) =>
    engine._propagateTsince(tsinceMinutes);
