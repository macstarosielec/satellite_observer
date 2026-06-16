// TEME -> ECEF rotation by GMST (library-private).

import 'dart:math' as math;

import 'package:satellite_observer/src/domain/eci_state.dart';
import 'package:satellite_observer/src/domain/geo/vector3.dart';
import 'package:satellite_observer/src/domain/time/gmst.dart';

/// An Earth-Centred, Earth-Fixed (ECEF / ITRF-approx) state.
///
/// Position is in kilometres, velocity in kilometres per second, both in the
/// rotating ECEF frame. This is an internal carrier between the TEME->ECEF
/// rotation and the topocentric stage; it is not exported.
class EcefState {
  /// Creates an [EcefState] from an ECEF [position] and [velocity].
  const EcefState(this.position, this.velocity);

  /// ECEF position, in kilometres.
  final Vector3 position;

  /// ECEF velocity, in kilometres per second.
  final Vector3 velocity;
}

/// Rotates the TEME [state] into the ECEF frame.
///
/// The rotation is about the Z axis by the Greenwich Mean Sidereal Time at the
/// state's UTC instant (ADR-4): a pure sidereal-time spin with no polar
/// motion, nutation or other EOP corrections (NG5).
///
/// Position transforms by the rotation `R3(theta)`:
///
/// ```text
/// x_ecef =  cos(theta) * x_teme + sin(theta) * y_teme
/// y_ecef = -sin(theta) * x_teme + cos(theta) * y_teme
/// z_ecef =  z_teme
/// ```
///
/// Velocity additionally carries the frame-rotation term so that range-rate is
/// computed in the rotating frame:
///
/// ```text
/// v_ecef = R3(theta) * v_teme - omega_earth x r_ecef
/// ```
///
/// with `omega_earth = (0, 0, earthRotationRateRadPerSec)`.
EcefState temeToEcef(EciState state) {
  final theta = greenwichMeanSiderealTime(state.utc);
  final cosT = math.cos(theta);
  final sinT = math.sin(theta);

  final r = state.position;
  final v = state.velocity;

  final xEcef = cosT * r.x + sinT * r.y;
  final yEcef = -sinT * r.x + cosT * r.y;
  final zEcef = r.z;

  // Rotate velocity into the frame, then subtract omega x r_ecef so the
  // result is the time derivative as seen in the rotating ECEF frame.
  final vxRot = cosT * v.x + sinT * v.y;
  final vyRot = -sinT * v.x + cosT * v.y;
  final vzRot = v.z;

  const omega = earthRotationRateRadPerSec;
  // omega x r_ecef = (-omega * y, omega * x, 0).
  final vxEcef = vxRot + omega * yEcef;
  final vyEcef = vyRot - omega * xEcef;
  final vzEcef = vzRot;

  return EcefState(
    Vector3(xEcef, yEcef, zEcef),
    Vector3(vxEcef, vyEcef, vzEcef),
  );
}
