// Faithful float64 port of Vallado's flat, assignment-heavy SGP4 step;
// suppress cascade and int-literal style lints so the math stays aligned with
// the reference for auditability.
// ignore_for_file: cascade_invocations, prefer_int_literals

import 'dart:math' as math;

import 'package:satellite_observer/src/domain/geo/vector3.dart';
import 'package:satellite_observer/src/propagation/sgp4/deep_space.dart';
import 'package:satellite_observer/src/propagation/sgp4/sgp4_satellite.dart';

// Core SGP4/SDP4 propagation step ported from the MIT-licensed python-sgp4
// (Brandon Rhodes), derived from Vallado, Crawford, Hujsak, Kelso,
// "Revisiting Spacetrack Report #3", AIAA 2006-6753.

const double _twopi = 2.0 * math.pi;

/// Result of a single SGP4 propagation step.
///
/// [error] is 0 on success or one of the Vallado error codes. When [error] is
/// nonzero, [position] and [velocity] hold NaN components and must not be used.
class Sgp4Result {
  /// Creates a result with the given [error] code, [position] and [velocity].
  const Sgp4Result(this.error, this.position, this.velocity);

  /// SGP4 error code (0 = success).
  final int error;

  /// TEME position in kilometres.
  final Vector3 position;

  /// TEME velocity in kilometres per second.
  final Vector3 velocity;
}

const Vector3 _nanVector = Vector3(double.nan, double.nan, double.nan);

/// Propagates [s] to [tsince] minutes past epoch, returning the TEME state.
Sgp4Result sgp4Step(Sgp4Satellite s, double tsince) {
  const temp4 = 1.5e-12;
  const x2o3 = 2.0 / 3.0;
  final vkmpersec = s.constants.radiusearthkm * s.constants.xke / 60.0;

  s.t = tsince;
  s.error = 0;

  // ---- update for secular gravity and atmospheric drag ----
  final xmdf = s.mo + s.mdot * s.t;
  final argpdf = s.argpo + s.argpdot * s.t;
  final nodedf = s.nodeo + s.nodedot * s.t;
  var argpm = argpdf;
  var mm = xmdf;
  final t2 = s.t * s.t;
  var nodem = nodedf + s.nodecf * t2;
  var tempa = 1.0 - s.cc1 * s.t;
  var tempe = s.bstar * s.cc4 * s.t;
  var templ = s.t2cof * t2;

  if (s.isimp != 1) {
    final delomg = s.omgcof * s.t;
    final delmtemp = 1.0 + s.eta * math.cos(xmdf);
    final delm = s.xmcof * (delmtemp * delmtemp * delmtemp - s.delmo);
    final temp = delomg + delm;
    mm = xmdf + temp;
    argpm = argpdf - temp;
    final t3 = t2 * s.t;
    final t4 = t3 * s.t;
    tempa = tempa - s.d2 * t2 - s.d3 * t3 - s.d4 * t4;
    tempe = tempe + s.bstar * s.cc5 * (math.sin(mm) - s.sinmao);
    templ = templ + s.t3cof * t3 + t4 * (s.t4cof + s.t * s.t5cof);
  }

  var nm = s.noUnkozai;
  var em = s.ecco;
  var inclm = s.inclo;
  if (s.method == 'd') {
    final tc = s.t;
    final r = dspace(
      s,
      tc: tc,
      em0: em,
      argpm0: argpm,
      inclm0: inclm,
      mm0: mm,
      nodem0: nodem,
      nm0: nm,
    );
    s.atime = r.atime;
    s.xli = r.xli;
    s.xni = r.xni;
    em = r.em;
    argpm = r.argpm;
    inclm = r.inclm;
    mm = r.mm;
    nodem = r.nodem;
    nm = r.nm;
  }

  if (nm <= 0.0) {
    s.error = 2;
    return const Sgp4Result(2, _nanVector, _nanVector);
  }

  final am = math.pow(s.constants.xke / nm, x2o3).toDouble() * tempa * tempa;
  nm = s.constants.xke / math.pow(am, 1.5);
  em = em - tempe;

  if (em >= 1.0 || em < -0.001) {
    s.error = 1;
    return const Sgp4Result(1, _nanVector, _nanVector);
  }

  if (em < 1.0e-6) em = 1.0e-6;
  mm = mm + s.noUnkozai * templ;
  var xlm = mm + argpm + nodem;

  nodem = nodem >= 0.0 ? nodem % _twopi : -((-nodem) % _twopi);
  argpm = argpm % _twopi;
  xlm = xlm % _twopi;
  mm = (xlm - argpm - nodem) % _twopi;

  s.am = am;
  s.em = em;
  s.im = inclm;
  s.bigOm = nodem;
  s.om = argpm;
  s.mm = mm;
  s.nm = nm;

  final sinim = math.sin(inclm);
  final cosim = math.cos(inclm);

  // ---- add lunar-solar periodics ----
  var ep = em;
  var xincp = inclm;
  var argpp = argpm;
  var nodep = nodem;
  var mp = mm;
  var sinip = sinim;
  var cosip = cosim;
  if (s.method == 'd') {
    final r = dpper(
      s,
      inclo: s.inclo,
      init: 'n',
      ep: ep,
      inclp: xincp,
      nodep: nodep,
      argpp: argpp,
      mp: mp,
      opsmode: s.operationmode,
    );
    ep = r.ep;
    xincp = r.inclp;
    nodep = r.nodep;
    argpp = r.argpp;
    mp = r.mp;

    if (xincp < 0.0) {
      xincp = -xincp;
      nodep = nodep + math.pi;
      argpp = argpp - math.pi;
    }

    if (ep < 0.0 || ep > 1.0) {
      s.error = 3;
      return const Sgp4Result(3, _nanVector, _nanVector);
    }
  }

  // ---- long period periodics ----
  if (s.method == 'd') {
    sinip = math.sin(xincp);
    cosip = math.cos(xincp);
    s.aycof = -0.5 * s.constants.j3oj2 * sinip;
    if ((cosip + 1.0).abs() > 1.5e-12) {
      s.xlcof = -0.25 *
          s.constants.j3oj2 *
          sinip *
          (3.0 + 5.0 * cosip) /
          (1.0 + cosip);
    } else {
      s.xlcof = -0.25 * s.constants.j3oj2 * sinip * (3.0 + 5.0 * cosip) / temp4;
    }
  }

  final axnl = ep * math.cos(argpp);
  var temp = 1.0 / (am * (1.0 - ep * ep));
  final aynl = ep * math.sin(argpp) + temp * s.aycof;
  final xl = mp + argpp + nodep + temp * s.xlcof * axnl;

  // ---- solve Kepler's equation ----
  final u = (xl - nodep) % _twopi;
  var eo1 = u;
  var tem5 = 9999.9;
  var ktr = 1;
  var sineo1 = 0.0;
  var coseo1 = 0.0;
  while (tem5.abs() >= 1.0e-12 && ktr <= 10) {
    sineo1 = math.sin(eo1);
    coseo1 = math.cos(eo1);
    tem5 = 1.0 - coseo1 * axnl - sineo1 * aynl;
    tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5;
    if (tem5.abs() >= 0.95) tem5 = tem5 > 0.0 ? 0.95 : -0.95;
    eo1 = eo1 + tem5;
    ktr = ktr + 1;
  }

  // ---- short period preliminary quantities ----
  final ecose = axnl * coseo1 + aynl * sineo1;
  final esine = axnl * sineo1 - aynl * coseo1;
  final el2 = axnl * axnl + aynl * aynl;
  final pl = am * (1.0 - el2);
  if (pl < 0.0) {
    s.error = 4;
    return const Sgp4Result(4, _nanVector, _nanVector);
  }

  final rl = am * (1.0 - ecose);
  final rdotl = math.sqrt(am) * esine / rl;
  final rvdotl = math.sqrt(pl) / rl;
  final betal = math.sqrt(1.0 - el2);
  temp = esine / (1.0 + betal);
  final sinu = am / rl * (sineo1 - aynl - axnl * temp);
  final cosu = am / rl * (coseo1 - axnl + aynl * temp);
  var su = math.atan2(sinu, cosu);
  final sin2u = (cosu + cosu) * sinu;
  final cos2u = 1.0 - 2.0 * sinu * sinu;
  temp = 1.0 / pl;
  final temp1 = 0.5 * s.constants.j2 * temp;
  final temp2 = temp1 * temp;

  if (s.method == 'd') {
    final cosisq = cosip * cosip;
    s.con41 = 3.0 * cosisq - 1.0;
    s.x1mth2 = 1.0 - cosisq;
    s.x7thm1 = 7.0 * cosisq - 1.0;
  }

  final mrt = rl * (1.0 - 1.5 * temp2 * betal * s.con41) +
      0.5 * temp1 * s.x1mth2 * cos2u;
  su = su - 0.25 * temp2 * s.x7thm1 * sin2u;
  final xnode = nodep + 1.5 * temp2 * cosip * sin2u;
  final xinc = xincp + 1.5 * temp2 * cosip * sinip * cos2u;
  final mvt = rdotl - nm * temp1 * s.x1mth2 * sin2u / s.constants.xke;
  final rvdot = rvdotl +
      nm * temp1 * (s.x1mth2 * cos2u + 1.5 * s.con41) / s.constants.xke;

  // ---- orientation vectors ----
  final sinsu = math.sin(su);
  final cossu = math.cos(su);
  final snod = math.sin(xnode);
  final cnod = math.cos(xnode);
  final sini = math.sin(xinc);
  final cosi = math.cos(xinc);
  final xmx = -snod * cosi;
  final xmy = cnod * cosi;
  final ux = xmx * sinsu + cnod * cossu;
  final uy = xmy * sinsu + snod * cossu;
  final uz = sini * sinsu;
  final vx = xmx * cossu - cnod * sinsu;
  final vy = xmy * cossu - snod * sinsu;
  final vz = sini * cossu;

  // ---- position and velocity (km and km/s) ----
  final mr = mrt * s.constants.radiusearthkm;
  final position = Vector3(mr * ux, mr * uy, mr * uz);
  final velocity = Vector3(
    (mvt * ux + rvdot * vx) * vkmpersec,
    (mvt * uy + rvdot * vy) * vkmpersec,
    (mvt * uz + rvdot * vz) * vkmpersec,
  );

  if (mrt < 1.0) {
    s.error = 6;
    return Sgp4Result(6, position, velocity);
  }

  return Sgp4Result(0, position, velocity);
}
