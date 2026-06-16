// Faithful float64 port of Vallado's flat sgp4init/initl; suppress cascade and
// int-literal style lints so the math stays aligned with the reference for
// auditability.
// ignore_for_file: cascade_invocations, prefer_int_literals

import 'dart:math' as math;

import 'package:satellite_observer/src/propagation/sgp4/deep_space.dart';
import 'package:satellite_observer/src/propagation/sgp4/sgp4_core.dart';
import 'package:satellite_observer/src/propagation/sgp4/sgp4_satellite.dart';

// SGP4 initialisation (sgp4init, initl, gstime) ported from the MIT-licensed
// python-sgp4 (Brandon Rhodes), derived from Vallado, Crawford, Hujsak, Kelso,
// "Revisiting Spacetrack Report #3", AIAA 2006-6753.

const double _twopi = 2.0 * math.pi;
const double _deg2rad = math.pi / 180.0;

/// Greenwich sidereal time (radians) for a UT1 Julian date [jdut1].
double gstime(double jdut1) {
  final tut1 = (jdut1 - 2451545.0) / 36525.0;
  var temp = -6.2e-6 * tut1 * tut1 * tut1 +
      0.093104 * tut1 * tut1 +
      (876600.0 * 3600 + 8640184.812866) * tut1 +
      67310.54841;
  temp = (temp * _deg2rad / 240.0) % _twopi;
  if (temp < 0.0) temp += _twopi;
  return temp;
}

class _InitlResult {
  _InitlResult({
    required this.no,
    required this.ainv,
    required this.ao,
    required this.con41,
    required this.con42,
    required this.cosio,
    required this.cosio2,
    required this.eccsq,
    required this.omeosq,
    required this.posq,
    required this.rp,
    required this.rteosq,
    required this.sinio,
    required this.gsto,
  });

  final double no;
  final double ainv;
  final double ao;
  final double con41;
  final double con42;
  final double cosio;
  final double cosio2;
  final double eccsq;
  final double omeosq;
  final double posq;
  final double rp;
  final double rteosq;
  final double sinio;
  final double gsto;
}

_InitlResult _initl(
  Sgp4Satellite s, {
  required double ecco,
  required double epoch,
  required double inclo,
  required double no0,
  required String opsmode,
}) {
  final xke = s.constants.xke;
  final j2 = s.constants.j2;
  const x2o3 = 2.0 / 3.0;

  final eccsq = ecco * ecco;
  final omeosq = 1.0 - eccsq;
  final rteosq = math.sqrt(omeosq);
  final cosio = math.cos(inclo);
  final cosio2 = cosio * cosio;

  // ---- un-kozai the mean motion ----
  final ak = math.pow(xke / no0, x2o3).toDouble();
  final d1 = 0.75 * j2 * (3.0 * cosio2 - 1.0) / (rteosq * omeosq);
  var del = d1 / (ak * ak);
  final adel =
      ak * (1.0 - del * del - del * (1.0 / 3.0 + 134.0 * del * del / 81.0));
  del = d1 / (adel * adel);
  final no = no0 / (1.0 + del);

  final ao = math.pow(xke / no, x2o3).toDouble();
  final sinio = math.sin(inclo);
  final po = ao * omeosq;
  final con42 = 1.0 - 5.0 * cosio2;
  final con41 = -con42 - cosio2 - cosio2;
  final ainv = 1.0 / ao;
  final posq = po * po;
  final rp = ao * (1.0 - ecco);

  double gsto;
  if (opsmode == 'a') {
    final ts70 = epoch - 7305.0;
    final ds70 = (ts70 + 1.0e-8).floorToDouble();
    final tfrac = ts70 - ds70;
    const c1 = 1.72027916940703639e-2;
    const thgr70 = 1.7321343856509374;
    const fk5r = 5.07551419432269442e-15;
    const c1p2p = c1 + _twopi;
    gsto = (thgr70 + c1 * ds70 + c1p2p * tfrac + ts70 * ts70 * fk5r) % _twopi;
    if (gsto < 0.0) gsto = gsto + _twopi;
  } else {
    gsto = gstime(epoch + 2433281.5);
  }

  return _InitlResult(
    no: no,
    ainv: ainv,
    ao: ao,
    con41: con41,
    con42: con42,
    cosio: cosio,
    cosio2: cosio2,
    eccsq: eccsq,
    omeosq: omeosq,
    posq: posq,
    rp: rp,
    rteosq: rteosq,
    sinio: sinio,
    gsto: gsto,
  );
}

/// Initialises [s] for SGP4/SDP4 propagation.
///
/// [epoch] is the epoch time in days from 1950 Jan 0.0. The satellite's mean
/// elements (bstar, ndot, nddot, ecco, argpo, inclo, mo, noKozai, nodeo) must
/// already be populated on [s]. After this call, [s] is ready for [sgp4Step].
void sgp4init(Sgp4Satellite s, {required double epoch}) {
  const temp4 = 1.5e-12;
  const x2o3 = 2.0 / 3.0;

  s
    ..isimp = 0
    ..method = 'n'
    ..aycof = 0.0
    ..con41 = 0.0
    ..cc1 = 0.0
    ..cc4 = 0.0
    ..cc5 = 0.0
    ..d2 = 0.0
    ..d3 = 0.0
    ..d4 = 0.0
    ..delmo = 0.0
    ..eta = 0.0
    ..argpdot = 0.0
    ..omgcof = 0.0
    ..sinmao = 0.0
    ..t = 0.0
    ..t2cof = 0.0
    ..t3cof = 0.0
    ..t4cof = 0.0
    ..t5cof = 0.0
    ..x1mth2 = 0.0
    ..x7thm1 = 0.0
    ..mdot = 0.0
    ..nodedot = 0.0
    ..xlcof = 0.0
    ..xmcof = 0.0
    ..nodecf = 0.0;

  final radiusearthkm = s.constants.radiusearthkm;
  final ss = 78.0 / radiusearthkm + 1.0;
  final qzms2ttemp = (120.0 - 78.0) / radiusearthkm;
  final qzms2t = qzms2ttemp * qzms2ttemp * qzms2ttemp * qzms2ttemp;

  s
    ..init = 'y'
    ..t = 0.0
    ..error = 0;

  final initl = _initl(
    s,
    ecco: s.ecco,
    epoch: epoch,
    inclo: s.inclo,
    no0: s.noKozai,
    opsmode: s.operationmode,
  );

  s
    ..noUnkozai = initl.no
    ..con41 = initl.con41
    ..gsto = initl.gsto;
  final con42 = initl.con42;
  final cosio = initl.cosio;
  final cosio2 = initl.cosio2;
  final eccsq = initl.eccsq;
  final omeosq = initl.omeosq;
  final posq = initl.posq;
  final rp = initl.rp;
  final rteosq = initl.rteosq;
  final sinio = initl.sinio;
  final ao = initl.ao;

  s
    ..a = math.pow(s.noUnkozai * s.constants.tumin, -2.0 / 3.0).toDouble()
    ..alta = s.a * (1.0 + s.ecco) - 1.0
    ..altp = s.a * (1.0 - s.ecco) - 1.0;

  if (omeosq >= 0.0 || s.noUnkozai >= 0.0) {
    s.isimp = 0;
    if (rp < 220.0 / radiusearthkm + 1.0) s.isimp = 1;
    var sfour = ss;
    var qzms24 = qzms2t;
    final perige = (rp - 1.0) * radiusearthkm;

    if (perige < 156.0) {
      sfour = perige - 78.0;
      if (perige < 98.0) sfour = 20.0;
      final qzms24temp = (120.0 - sfour) / radiusearthkm;
      qzms24 = qzms24temp * qzms24temp * qzms24temp * qzms24temp;
      sfour = sfour / radiusearthkm + 1.0;
    }

    final pinvsq = 1.0 / posq;
    final tsi = 1.0 / (ao - sfour);
    s.eta = ao * s.ecco * tsi;
    final etasq = s.eta * s.eta;
    final eeta = s.ecco * s.eta;
    final psisq = (1.0 - etasq).abs();
    final coef = qzms24 * math.pow(tsi, 4.0).toDouble();
    final coef1 = coef / math.pow(psisq, 3.5).toDouble();
    final cc2 = coef1 *
        s.noUnkozai *
        (ao * (1.0 + 1.5 * etasq + eeta * (4.0 + etasq)) +
            0.375 *
                s.constants.j2 *
                tsi /
                psisq *
                s.con41 *
                (8.0 + 3.0 * etasq * (8.0 + etasq)));
    s.cc1 = s.bstar * cc2;
    var cc3 = 0.0;
    if (s.ecco > 1.0e-4) {
      cc3 =
          -2.0 * coef * tsi * s.constants.j3oj2 * s.noUnkozai * sinio / s.ecco;
    }
    s.x1mth2 = 1.0 - cosio2;
    s.cc4 = 2.0 *
        s.noUnkozai *
        coef1 *
        ao *
        omeosq *
        (s.eta * (2.0 + 0.5 * etasq) +
            s.ecco * (0.5 + 2.0 * etasq) -
            s.constants.j2 *
                tsi /
                (ao * psisq) *
                (-3.0 *
                        s.con41 *
                        (1.0 - 2.0 * eeta + etasq * (1.5 - 0.5 * eeta)) +
                    0.75 *
                        s.x1mth2 *
                        (2.0 * etasq - eeta * (1.0 + etasq)) *
                        math.cos(2.0 * s.argpo)));
    s.cc5 = 2.0 *
        coef1 *
        ao *
        omeosq *
        (1.0 + 2.75 * (etasq + eeta) + eeta * etasq);
    final cosio4 = cosio2 * cosio2;
    final temp1 = 1.5 * s.constants.j2 * pinvsq * s.noUnkozai;
    final temp2 = 0.5 * temp1 * s.constants.j2 * pinvsq;
    final temp3 = -0.46875 * s.constants.j4 * pinvsq * pinvsq * s.noUnkozai;
    s.mdot = s.noUnkozai +
        0.5 * temp1 * rteosq * s.con41 +
        0.0625 * temp2 * rteosq * (13.0 - 78.0 * cosio2 + 137.0 * cosio4);
    s.argpdot = -0.5 * temp1 * con42 +
        0.0625 * temp2 * (7.0 - 114.0 * cosio2 + 395.0 * cosio4) +
        temp3 * (3.0 - 36.0 * cosio2 + 49.0 * cosio4);
    final xhdot1 = -temp1 * cosio;
    s.nodedot = xhdot1 +
        (0.5 * temp2 * (4.0 - 19.0 * cosio2) +
                2.0 * temp3 * (3.0 - 7.0 * cosio2)) *
            cosio;
    final xpidot = s.argpdot + s.nodedot;
    s.omgcof = s.bstar * cc3 * math.cos(s.argpo);
    s.xmcof = 0.0;
    if (s.ecco > 1.0e-4) s.xmcof = -x2o3 * coef * s.bstar / eeta;
    s.nodecf = 3.5 * omeosq * xhdot1 * s.cc1;
    s.t2cof = 1.5 * s.cc1;
    if ((cosio + 1.0).abs() > 1.5e-12) {
      s.xlcof = -0.25 *
          s.constants.j3oj2 *
          sinio *
          (3.0 + 5.0 * cosio) /
          (1.0 + cosio);
    } else {
      s.xlcof = -0.25 * s.constants.j3oj2 * sinio * (3.0 + 5.0 * cosio) / temp4;
    }
    s.aycof = -0.5 * s.constants.j3oj2 * sinio;
    final delmotemp = 1.0 + s.eta * math.cos(s.mo);
    s.delmo = delmotemp * delmotemp * delmotemp;
    s.sinmao = math.sin(s.mo);
    s.x7thm1 = 7.0 * cosio2 - 1.0;

    // ---- deep space initialization ----
    if (_twopi / s.noUnkozai >= 225.0) {
      s.method = 'd';
      s.isimp = 1;
      const tc = 0.0;
      final inclm = s.inclo;

      final d = dscom(
        s,
        epoch: epoch,
        ep: s.ecco,
        argpp: s.argpo,
        tc: tc,
        inclp: s.inclo,
        nodep: s.nodeo,
        np: s.noUnkozai,
      );

      // The eccentricity dsinit's resonance check needs is the value before
      // dpper perturbs it (matches the python-sgp4 sgp4init `em` local).
      final emPreDpper = s.ecco;

      final dp = dpper(
        s,
        inclo: inclm,
        init: s.init,
        ep: s.ecco,
        inclp: s.inclo,
        nodep: s.nodeo,
        argpp: s.argpo,
        mp: s.mo,
        opsmode: s.operationmode,
      );
      s
        ..ecco = dp.ep
        ..inclo = dp.inclp
        ..nodeo = dp.nodep
        ..argpo = dp.argpp
        ..mo = dp.mp;

      dsinit(
        s,
        d: d,
        tc: tc,
        xpidot: xpidot,
        eccsq: eccsq,
        em0: emPreDpper,
        argpm0: 0,
        inclm0: inclm,
        mm0: 0,
        nodem0: 0,
      );
    }

    // ---- set variables if not deep space ----
    if (s.isimp != 1) {
      final cc1sq = s.cc1 * s.cc1;
      s.d2 = 4.0 * ao * tsi * cc1sq;
      final temp = s.d2 * tsi * s.cc1 / 3.0;
      s.d3 = (17.0 * ao + sfour) * temp;
      s.d4 = 0.5 * temp * ao * tsi * (221.0 * ao + 31.0 * sfour) * s.cc1;
      s.t3cof = s.d2 + 2.0 * cc1sq;
      s.t4cof = 0.25 * (3.0 * s.d3 + s.cc1 * (12.0 * s.d2 + 10.0 * cc1sq));
      s.t5cof = 0.2 *
          (3.0 * s.d4 +
              12.0 * s.cc1 * s.d3 +
              6.0 * s.d2 * s.d2 +
              15.0 * cc1sq * (2.0 * s.d2 + cc1sq));
    }
  }

  // Propagate to zero epoch to initialize all others.
  sgp4Step(s, 0);
  s.init = 'n';
}
