// Library-internal SDP4 routines (never exported from the public barrel). The
// result-holder classes are flat bundles of named scratch values that mirror
// the reference's multi-value returns one-to-one, so we opt out of the
// member-doc lint for this file rather than document each transient field.
// Cascades and int-literal substitutions are also suppressed: this is a
// faithful float64 port of Vallado's flat assignment-heavy code, where the
// literal 0.0/2.0 forms and explicit `s.field =` reads keep the math aligned
// with the reference for auditability.
// ignore_for_file: public_member_api_docs, cascade_invocations
// ignore_for_file: prefer_int_literals

import 'dart:math' as math;

import 'package:satellite_observer/src/propagation/sgp4/sgp4_satellite.dart';

// Deep-space (SDP4) routines ported from the MIT-licensed python-sgp4
// (Brandon Rhodes), derived from Vallado, Crawford, Hujsak, Kelso,
// "Revisiting Spacetrack Report #3", AIAA 2006-6753.

const double _twopi = 2.0 * math.pi;

// Reduces x modulo 2*pi. The reference C code uses fmod, which may return a
// negative result for negative x; every caller here passes a non-negative
// argument, so for the inputs that actually occur this matches fmod exactly.
// (Dart's `%` differs from fmod only on negative operands - it always returns
// a non-negative result - so do not switch this to `.remainder()` or hand-roll
// a sign fix expecting non-negative callers: it would needlessly diverge from
// the reference's intent for the inputs we use.)
double _fmodTwoPi(double x) {
  final r = x % _twopi;
  return r;
}

/// Locals produced by [dscom] that [dsinit] needs.
class DscomResult {
  DscomResult({
    required this.cosim,
    required this.sinim,
    required this.emsq,
    required this.s1,
    required this.s2,
    required this.s3,
    required this.s4,
    required this.s5,
    required this.ss1,
    required this.ss2,
    required this.ss3,
    required this.ss4,
    required this.ss5,
    required this.sz1,
    required this.sz3,
    required this.sz11,
    required this.sz13,
    required this.sz21,
    required this.sz23,
    required this.sz31,
    required this.sz33,
    required this.z1,
    required this.z3,
    required this.z11,
    required this.z13,
    required this.z21,
    required this.z23,
    required this.z31,
    required this.z33,
    required this.nm,
  });

  final double cosim;
  final double sinim;
  final double emsq;
  final double s1;
  final double s2;
  final double s3;
  final double s4;
  final double s5;
  final double ss1;
  final double ss2;
  final double ss3;
  final double ss4;
  final double ss5;
  final double sz1;
  final double sz3;
  final double sz11;
  final double sz13;
  final double sz21;
  final double sz23;
  final double sz31;
  final double sz33;
  final double z1;
  final double z3;
  final double z11;
  final double z13;
  final double z21;
  final double z23;
  final double z31;
  final double z33;
  final double nm;
}

/// Provides deep-space common items used by the secular and periodic routines.
DscomResult dscom(
  Sgp4Satellite s, {
  required double epoch,
  required double ep,
  required double argpp,
  required double tc,
  required double inclp,
  required double nodep,
  required double np,
}) {
  const zes = 0.01675;
  const zel = 0.05490;
  const c1ss = 2.9864797e-6;
  const c1l = 4.7968065e-7;
  const zsinis = 0.39785416;
  const zcosis = 0.91744867;
  const zcosgs = 0.1945905;
  const zsings = -0.98088458;

  final nm = np;
  final em = ep;
  final snodm = math.sin(nodep);
  final cnodm = math.cos(nodep);
  final sinomm = math.sin(argpp);
  final cosomm = math.cos(argpp);
  final sinim = math.sin(inclp);
  final cosim = math.cos(inclp);
  final emsq = em * em;
  final betasq = 1.0 - emsq;
  final rtemsq = math.sqrt(betasq);

  s
    ..peo = 0.0
    ..pinco = 0.0
    ..plo = 0.0
    ..pgho = 0.0
    ..pho = 0.0;

  final day = epoch + 18261.5 + tc / 1440.0;
  final xnodce = _fmodTwoPi(4.5236020 - 9.2422029e-4 * day);
  final stem = math.sin(xnodce);
  final ctem = math.cos(xnodce);
  final zcosil = 0.91375164 - 0.03568096 * ctem;
  final zsinil = math.sqrt(1.0 - zcosil * zcosil);
  final zsinhl = 0.089683511 * stem / zsinil;
  final zcoshl = math.sqrt(1.0 - zsinhl * zsinhl);
  final gam = 5.8351514 + 0.0019443680 * day;
  var zx = 0.39785416 * stem / zsinil;
  final zy = zcoshl * ctem + 0.91744867 * zsinhl * stem;
  zx = math.atan2(zx, zy);
  zx = gam + zx - xnodce;
  final zcosgl = math.cos(zx);
  final zsingl = math.sin(zx);

  var zcosg = zcosgs;
  var zsing = zsings;
  var zcosi = zcosis;
  var zsini = zsinis;
  var zcosh = cnodm;
  var zsinh = snodm;
  var cc = c1ss;
  final xnoi = 1.0 / nm;

  var s1 = 0.0;
  var s2 = 0.0;
  var s3 = 0.0;
  var s4 = 0.0;
  var s5 = 0.0;
  var s6 = 0.0;
  var s7 = 0.0;
  var ss1 = 0.0;
  var ss2 = 0.0;
  var ss3 = 0.0;
  var ss4 = 0.0;
  var ss5 = 0.0;
  var ss6 = 0.0;
  var ss7 = 0.0;
  var sz1 = 0.0;
  var sz2 = 0.0;
  var sz3 = 0.0;
  var sz11 = 0.0;
  var sz12 = 0.0;
  var sz13 = 0.0;
  var sz21 = 0.0;
  var sz22 = 0.0;
  var sz23 = 0.0;
  var sz31 = 0.0;
  var sz32 = 0.0;
  var sz33 = 0.0;
  var z1 = 0.0;
  var z2 = 0.0;
  var z3 = 0.0;
  var z11 = 0.0;
  var z12 = 0.0;
  var z13 = 0.0;
  var z21 = 0.0;
  var z22 = 0.0;
  var z23 = 0.0;
  var z31 = 0.0;
  var z32 = 0.0;
  var z33 = 0.0;

  for (var lsflg = 1; lsflg <= 2; lsflg++) {
    final a1 = zcosg * zcosh + zsing * zcosi * zsinh;
    final a3 = -zsing * zcosh + zcosg * zcosi * zsinh;
    final a7 = -zcosg * zsinh + zsing * zcosi * zcosh;
    final a8 = zsing * zsini;
    final a9 = zsing * zsinh + zcosg * zcosi * zcosh;
    final a10 = zcosg * zsini;
    final a2 = cosim * a7 + sinim * a8;
    final a4 = cosim * a9 + sinim * a10;
    final a5 = -sinim * a7 + cosim * a8;
    final a6 = -sinim * a9 + cosim * a10;

    final x1 = a1 * cosomm + a2 * sinomm;
    final x2 = a3 * cosomm + a4 * sinomm;
    final x3 = -a1 * sinomm + a2 * cosomm;
    final x4 = -a3 * sinomm + a4 * cosomm;
    final x5 = a5 * sinomm;
    final x6 = a6 * sinomm;
    final x7 = a5 * cosomm;
    final x8 = a6 * cosomm;

    z31 = 12.0 * x1 * x1 - 3.0 * x3 * x3;
    z32 = 24.0 * x1 * x2 - 6.0 * x3 * x4;
    z33 = 12.0 * x2 * x2 - 3.0 * x4 * x4;
    z1 = 3.0 * (a1 * a1 + a2 * a2) + z31 * emsq;
    z2 = 6.0 * (a1 * a3 + a2 * a4) + z32 * emsq;
    z3 = 3.0 * (a3 * a3 + a4 * a4) + z33 * emsq;
    z11 = -6.0 * a1 * a5 + emsq * (-24.0 * x1 * x7 - 6.0 * x3 * x5);
    z12 = -6.0 * (a1 * a6 + a3 * a5) +
        emsq * (-24.0 * (x2 * x7 + x1 * x8) - 6.0 * (x3 * x6 + x4 * x5));
    z13 = -6.0 * a3 * a6 + emsq * (-24.0 * x2 * x8 - 6.0 * x4 * x6);
    z21 = 6.0 * a2 * a5 + emsq * (24.0 * x1 * x5 - 6.0 * x3 * x7);
    z22 = 6.0 * (a4 * a5 + a2 * a6) +
        emsq * (24.0 * (x2 * x5 + x1 * x6) - 6.0 * (x4 * x7 + x3 * x8));
    z23 = 6.0 * a4 * a6 + emsq * (24.0 * x2 * x6 - 6.0 * x4 * x8);
    z1 = z1 + z1 + betasq * z31;
    z2 = z2 + z2 + betasq * z32;
    z3 = z3 + z3 + betasq * z33;
    s3 = cc * xnoi;
    s2 = -0.5 * s3 / rtemsq;
    s4 = s3 * rtemsq;
    s1 = -15.0 * em * s4;
    s5 = x1 * x3 + x2 * x4;
    s6 = x2 * x3 + x1 * x4;
    s7 = x2 * x4 - x1 * x3;

    if (lsflg == 1) {
      ss1 = s1;
      ss2 = s2;
      ss3 = s3;
      ss4 = s4;
      ss5 = s5;
      ss6 = s6;
      ss7 = s7;
      sz1 = z1;
      sz2 = z2;
      sz3 = z3;
      sz11 = z11;
      sz12 = z12;
      sz13 = z13;
      sz21 = z21;
      sz22 = z22;
      sz23 = z23;
      sz31 = z31;
      sz32 = z32;
      sz33 = z33;
      zcosg = zcosgl;
      zsing = zsingl;
      zcosi = zcosil;
      zsini = zsinil;
      zcosh = zcoshl * cnodm + zsinhl * snodm;
      zsinh = snodm * zcoshl - cnodm * zsinhl;
      cc = c1l;
    }
  }

  s
    ..zmol = _fmodTwoPi(4.7199672 + 0.22997150 * day - gam)
    ..zmos = _fmodTwoPi(6.2565837 + 0.017201977 * day)
    // ---- solar terms ----
    ..se2 = 2.0 * ss1 * ss6
    ..se3 = 2.0 * ss1 * ss7
    ..si2 = 2.0 * ss2 * sz12
    ..si3 = 2.0 * ss2 * (sz13 - sz11)
    ..sl2 = -2.0 * ss3 * sz2
    ..sl3 = -2.0 * ss3 * (sz3 - sz1)
    ..sl4 = -2.0 * ss3 * (-21.0 - 9.0 * emsq) * zes
    ..sgh2 = 2.0 * ss4 * sz32
    ..sgh3 = 2.0 * ss4 * (sz33 - sz31)
    ..sgh4 = -18.0 * ss4 * zes
    ..sh2 = -2.0 * ss2 * sz22
    ..sh3 = -2.0 * ss2 * (sz23 - sz21)
    // ---- lunar terms ----
    ..ee2 = 2.0 * s1 * s6
    ..e3 = 2.0 * s1 * s7
    ..xi2 = 2.0 * s2 * z12
    ..xi3 = 2.0 * s2 * (z13 - z11)
    ..xl2 = -2.0 * s3 * z2
    ..xl3 = -2.0 * s3 * (z3 - z1)
    ..xl4 = -2.0 * s3 * (-21.0 - 9.0 * emsq) * zel
    ..xgh2 = 2.0 * s4 * z32
    ..xgh3 = 2.0 * s4 * (z33 - z31)
    ..xgh4 = -18.0 * s4 * zel
    ..xh2 = -2.0 * s2 * z22
    ..xh3 = -2.0 * s2 * (z23 - z21);

  return DscomResult(
    cosim: cosim,
    sinim: sinim,
    emsq: emsq,
    s1: s1,
    s2: s2,
    s3: s3,
    s4: s4,
    s5: s5,
    ss1: ss1,
    ss2: ss2,
    ss3: ss3,
    ss4: ss4,
    ss5: ss5,
    sz1: sz1,
    sz3: sz3,
    sz11: sz11,
    sz13: sz13,
    sz21: sz21,
    sz23: sz23,
    sz31: sz31,
    sz33: sz33,
    z1: z1,
    z3: z3,
    z11: z11,
    z13: z13,
    z21: z21,
    z23: z23,
    z31: z31,
    z33: z33,
    nm: nm,
  );
}

/// Perturbed osculating elements after applying lunar-solar periodics.
class DpperResult {
  DpperResult(this.ep, this.inclp, this.nodep, this.argpp, this.mp);

  final double ep;
  final double inclp;
  final double nodep;
  final double argpp;
  final double mp;
}

/// Applies the lunar-solar periodic perturbations (deep-space `dpper`).
DpperResult dpper(
  Sgp4Satellite s, {
  required double inclo,
  required String init,
  required double ep,
  required double inclp,
  required double nodep,
  required double argpp,
  required double mp,
  required String opsmode,
}) {
  const zns = 1.19459e-5;
  const zes = 0.01675;
  const znl = 1.5835218e-4;
  const zel = 0.05490;

  var epOut = ep;
  var inclpOut = inclp;
  var nodepOut = nodep;
  var argppOut = argpp;
  var mpOut = mp;

  var zm = s.zmos + zns * s.t;
  if (init == 'y') zm = s.zmos;
  var zf = zm + 2.0 * zes * math.sin(zm);
  var sinzf = math.sin(zf);
  var f2 = 0.5 * sinzf * sinzf - 0.25;
  var f3 = -0.5 * sinzf * math.cos(zf);
  final ses = s.se2 * f2 + s.se3 * f3;
  final sis = s.si2 * f2 + s.si3 * f3;
  final sls = s.sl2 * f2 + s.sl3 * f3 + s.sl4 * sinzf;
  final sghs = s.sgh2 * f2 + s.sgh3 * f3 + s.sgh4 * sinzf;
  final shs = s.sh2 * f2 + s.sh3 * f3;

  zm = s.zmol + znl * s.t;
  if (init == 'y') zm = s.zmol;
  zf = zm + 2.0 * zel * math.sin(zm);
  sinzf = math.sin(zf);
  f2 = 0.5 * sinzf * sinzf - 0.25;
  f3 = -0.5 * sinzf * math.cos(zf);
  final sel = s.ee2 * f2 + s.e3 * f3;
  final sil = s.xi2 * f2 + s.xi3 * f3;
  final sll = s.xl2 * f2 + s.xl3 * f3 + s.xl4 * sinzf;
  final sghl = s.xgh2 * f2 + s.xgh3 * f3 + s.xgh4 * sinzf;
  final shll = s.xh2 * f2 + s.xh3 * f3;

  var pe = ses + sel;
  var pinc = sis + sil;
  var pl = sls + sll;
  var pgh = sghs + sghl;
  var ph = shs + shll;

  if (init == 'n') {
    pe = pe - s.peo;
    pinc = pinc - s.pinco;
    pl = pl - s.plo;
    pgh = pgh - s.pgho;
    ph = ph - s.pho;
    inclpOut = inclpOut + pinc;
    epOut = epOut + pe;
    final sinip = math.sin(inclpOut);
    final cosip = math.cos(inclpOut);

    if (inclpOut >= 0.2) {
      ph /= sinip;
      pgh -= cosip * ph;
      argppOut += pgh;
      nodepOut += ph;
      mpOut += pl;
    } else {
      final sinop = math.sin(nodepOut);
      final cosop = math.cos(nodepOut);
      var alfdp = sinip * sinop;
      var betdp = sinip * cosop;
      final dalf = ph * cosop + pinc * cosip * sinop;
      final dbet = -ph * sinop + pinc * cosip * cosop;
      alfdp = alfdp + dalf;
      betdp = betdp + dbet;
      nodepOut = nodepOut >= 0.0 ? nodepOut % _twopi : -((-nodepOut) % _twopi);
      if (nodepOut < 0.0 && opsmode == 'a') nodepOut = nodepOut + _twopi;
      final xls =
          mpOut + argppOut + pl + pgh + (cosip - pinc * sinip) * nodepOut;
      final xnoh = nodepOut;
      nodepOut = math.atan2(alfdp, betdp);
      if (nodepOut < 0.0 && opsmode == 'a') nodepOut = nodepOut + _twopi;
      if ((xnoh - nodepOut).abs() > math.pi) {
        if (nodepOut < xnoh) {
          nodepOut = nodepOut + _twopi;
        } else {
          nodepOut = nodepOut - _twopi;
        }
      }
      mpOut += pl;
      argppOut = xls - mpOut - cosip * nodepOut;
    }
  }

  return DpperResult(epOut, inclpOut, nodepOut, argppOut, mpOut);
}

/// Mean elements updated by [dsinit].
class DsinitResult {
  DsinitResult({
    required this.em,
    required this.argpm,
    required this.inclm,
    required this.mm,
    required this.nm,
    required this.nodem,
  });

  final double em;
  final double argpm;
  final double inclm;
  final double mm;
  final double nm;
  final double nodem;
}

/// Provides deep-space geopotential resonance contributions (`dsinit`).
DsinitResult dsinit(
  Sgp4Satellite s, {
  required DscomResult d,
  required double tc,
  required double xpidot,
  required double eccsq,
  required double em0,
  required double argpm0,
  required double inclm0,
  required double mm0,
  required double nodem0,
}) {
  const q22 = 1.7891679e-6;
  const q31 = 2.1460748e-6;
  const q33 = 2.2123015e-7;
  const root22 = 1.7891679e-6;
  const root44 = 7.3636953e-9;
  const root54 = 2.1765803e-9;
  const rptim = 4.37526908801129966e-3;
  const root32 = 3.7393792e-7;
  const root52 = 1.1428639e-7;
  const x2o3 = 2.0 / 3.0;
  const znl = 1.5835218e-4;
  const zns = 1.19459e-5;

  final xke = s.constants.xke;
  final cosim = d.cosim;
  final sinim = d.sinim;
  var emsq = d.emsq;
  final argpo = s.argpo;
  final no = s.noUnkozai;

  var em = em0;
  var argpm = argpm0;
  var inclm = inclm0;
  var mm = mm0;
  var nm = d.nm;
  var nodem = nodem0;

  s.irez = 0;
  if (nm > 0.0034906585 && nm < 0.0052359877) s.irez = 1;
  if (nm >= 8.26e-3 && nm <= 9.24e-3 && em >= 0.5) s.irez = 2;

  // ---- solar terms ----
  final ses = d.ss1 * zns * d.ss5;
  final sis = d.ss2 * zns * (d.sz11 + d.sz13);
  final sls = -zns * d.ss3 * (d.sz1 + d.sz3 - 14.0 - 6.0 * emsq);
  final sghs = d.ss4 * zns * (d.sz31 + d.sz33 - 6.0);
  var shs = -zns * d.ss2 * (d.sz21 + d.sz23);
  if (inclm < 5.2359877e-2 || inclm > math.pi - 5.2359877e-2) shs = 0.0;
  if (sinim != 0.0) shs = shs / sinim;
  final sgs = sghs - cosim * shs;

  // ---- lunar terms ----
  s.dedt = ses + d.s1 * znl * d.s5;
  s.didt = sis + d.s2 * znl * (d.z11 + d.z13);
  s.dmdt = sls - znl * d.s3 * (d.z1 + d.z3 - 14.0 - 6.0 * emsq);
  final sghl = d.s4 * znl * (d.z31 + d.z33 - 6.0);
  var shll = -znl * d.s2 * (d.z21 + d.z23);
  if (inclm < 5.2359877e-2 || inclm > math.pi - 5.2359877e-2) shll = 0.0;
  s.domdt = sgs + sghl;
  s.dnodt = shs;
  if (sinim != 0.0) {
    s.domdt = s.domdt - cosim / sinim * shll;
    s.dnodt = s.dnodt + shll / sinim;
  }

  final theta = _fmodTwoPi(s.gsto + tc * rptim);
  em = em + s.dedt * s.t;
  inclm = inclm + s.didt * s.t;
  argpm = argpm + s.domdt * s.t;
  nodem = nodem + s.dnodt * s.t;
  mm = mm + s.dmdt * s.t;

  if (s.irez != 0) {
    final aonv = math.pow(nm / xke, x2o3).toDouble();

    if (s.irez == 2) {
      final cosisq = cosim * cosim;
      final emo = em;
      em = s.ecco;
      final emsqo = emsq;
      emsq = eccsq;
      final eoc = em * emsq;
      final g201 = -0.306 - (em - 0.64) * 0.440;

      double g211;
      double g310;
      double g322;
      double g410;
      double g422;
      double g520;
      if (em <= 0.65) {
        g211 = 3.616 - 13.2470 * em + 16.2900 * emsq;
        g310 = -19.302 + 117.3900 * em - 228.4190 * emsq + 156.5910 * eoc;
        g322 = -18.9068 + 109.7927 * em - 214.6334 * emsq + 146.5816 * eoc;
        g410 = -41.122 + 242.6940 * em - 471.0940 * emsq + 313.9530 * eoc;
        g422 = -146.407 + 841.8800 * em - 1629.014 * emsq + 1083.4350 * eoc;
        g520 = -532.114 + 3017.977 * em - 5740.032 * emsq + 3708.2760 * eoc;
      } else {
        g211 = -72.099 + 331.819 * em - 508.738 * emsq + 266.724 * eoc;
        g310 = -346.844 + 1582.851 * em - 2415.925 * emsq + 1246.113 * eoc;
        g322 = -342.585 + 1554.908 * em - 2366.899 * emsq + 1215.972 * eoc;
        g410 = -1052.797 + 4758.686 * em - 7193.992 * emsq + 3651.957 * eoc;
        g422 = -3581.690 + 16178.110 * em - 24462.770 * emsq + 12422.520 * eoc;
        if (em > 0.715) {
          g520 = -5149.66 + 29936.92 * em - 54087.36 * emsq + 31324.56 * eoc;
        } else {
          g520 = 1464.74 - 4664.75 * em + 3763.64 * emsq;
        }
      }

      double g533;
      double g521;
      double g532;
      if (em < 0.7) {
        g533 = -919.22770 + 4988.6100 * em - 9064.7700 * emsq + 5542.21 * eoc;
        g521 = -822.71072 + 4568.6173 * em - 8491.4146 * emsq + 5337.524 * eoc;
        g532 = -853.66600 + 4690.2500 * em - 8624.7700 * emsq + 5341.4 * eoc;
      } else {
        g533 = -37995.780 + 161616.52 * em - 229838.20 * emsq + 109377.94 * eoc;
        g521 = -51752.104 + 218913.95 * em - 309468.16 * emsq + 146349.42 * eoc;
        g532 = -40023.880 + 170470.89 * em - 242699.48 * emsq + 115605.82 * eoc;
      }

      final sini2 = sinim * sinim;
      final f220 = 0.75 * (1.0 + 2.0 * cosim + cosisq);
      final f221 = 1.5 * sini2;
      final f321 = 1.875 * sinim * (1.0 - 2.0 * cosim - 3.0 * cosisq);
      final f322 = -1.875 * sinim * (1.0 + 2.0 * cosim - 3.0 * cosisq);
      final f441 = 35.0 * sini2 * f220;
      final f442 = 39.3750 * sini2 * sini2;
      final f522 = 9.84375 *
          sinim *
          (sini2 * (1.0 - 2.0 * cosim - 5.0 * cosisq) +
              0.33333333 * (-2.0 + 4.0 * cosim + 6.0 * cosisq));
      final f523 = sinim *
          (4.92187512 * sini2 * (-2.0 - 4.0 * cosim + 10.0 * cosisq) +
              6.56250012 * (1.0 + 2.0 * cosim - 3.0 * cosisq));
      final f542 = 29.53125 *
          sinim *
          (2.0 - 8.0 * cosim + cosisq * (-12.0 + 8.0 * cosim + 10.0 * cosisq));
      final f543 = 29.53125 *
          sinim *
          (-2.0 - 8.0 * cosim + cosisq * (12.0 + 8.0 * cosim - 10.0 * cosisq));
      final xno2 = nm * nm;
      final ainv2 = aonv * aonv;
      var temp1 = 3.0 * xno2 * ainv2;
      var temp = temp1 * root22;
      s.d2201 = temp * f220 * g201;
      s.d2211 = temp * f221 * g211;
      temp1 = temp1 * aonv;
      temp = temp1 * root32;
      s.d3210 = temp * f321 * g310;
      s.d3222 = temp * f322 * g322;
      temp1 = temp1 * aonv;
      temp = 2.0 * temp1 * root44;
      s.d4410 = temp * f441 * g410;
      s.d4422 = temp * f442 * g422;
      temp1 = temp1 * aonv;
      temp = temp1 * root52;
      s.d5220 = temp * f522 * g520;
      s.d5232 = temp * f523 * g532;
      temp = 2.0 * temp1 * root54;
      s.d5421 = temp * f542 * g521;
      s.d5433 = temp * f543 * g533;
      s.xlamo = _fmodTwoPi(s.mo + s.nodeo + s.nodeo - theta - theta);
      s.xfact = s.mdot + s.dmdt + 2.0 * (s.nodedot + s.dnodt - rptim) - no;
      em = emo;
      emsq = emsqo;
    }

    if (s.irez == 1) {
      final g200 = 1.0 + emsq * (-2.5 + 0.8125 * emsq);
      final g310 = 1.0 + 2.0 * emsq;
      final g300 = 1.0 + emsq * (-6.0 + 6.60937 * emsq);
      final f220 = 0.75 * (1.0 + cosim) * (1.0 + cosim);
      final f311 =
          0.9375 * sinim * sinim * (1.0 + 3.0 * cosim) - 0.75 * (1.0 + cosim);
      var f330 = 1.0 + cosim;
      f330 = 1.875 * f330 * f330 * f330;
      s.del1 = 3.0 * nm * nm * aonv * aonv;
      s.del2 = 2.0 * s.del1 * f220 * g200 * q22;
      s.del3 = 3.0 * s.del1 * f330 * g300 * q33 * aonv;
      s.del1 = s.del1 * f311 * g310 * q31 * aonv;
      s.xlamo = _fmodTwoPi(s.mo + s.nodeo + argpo - theta);
      s.xfact = s.mdot + xpidot - rptim + s.dmdt + s.domdt + s.dnodt - no;
    }

    s.xli = s.xlamo;
    s.xni = no;
    s.atime = 0.0;
    nm = no;
  }

  return DsinitResult(
    em: em,
    argpm: argpm,
    inclm: inclm,
    mm: mm,
    nm: nm,
    nodem: nodem,
  );
}

/// Mean elements after the deep-space resonance integration step.
class DspaceResult {
  DspaceResult({
    required this.atime,
    required this.em,
    required this.argpm,
    required this.inclm,
    required this.xli,
    required this.mm,
    required this.xni,
    required this.nodem,
    required this.dndt,
    required this.nm,
  });

  final double atime;
  final double em;
  final double argpm;
  final double inclm;
  final double xli;
  final double mm;
  final double xni;
  final double nodem;
  final double dndt;
  final double nm;
}

/// Provides deep-space contributions via Euler-Maclaurin integration.
DspaceResult dspace(
  Sgp4Satellite s, {
  required double tc,
  required double em0,
  required double argpm0,
  required double inclm0,
  required double mm0,
  required double nodem0,
  required double nm0,
}) {
  const fasx2 = 0.13130908;
  const fasx4 = 2.8843198;
  const fasx6 = 0.37448087;
  const g22 = 5.7686396;
  const g32 = 0.95240898;
  const g44 = 1.8014998;
  const g52 = 1.0508330;
  const g54 = 4.4108898;
  const rptim = 4.37526908801129966e-3;
  const stepp = 720.0;
  const stepn = -720.0;
  const step2 = 259200.0;

  final no = s.noUnkozai;
  final argpo = s.argpo;
  final argpdot = s.argpdot;

  var atime = s.atime;
  var em = em0;
  var argpm = argpm0;
  var inclm = inclm0;
  var xli = s.xli;
  var mm = mm0;
  var xni = s.xni;
  var nodem = nodem0;
  var nm = nm0;

  var dndt = 0.0;
  final theta = _fmodTwoPi(s.gsto + tc * rptim);
  em = em + s.dedt * s.t;
  inclm = inclm + s.didt * s.t;
  argpm = argpm + s.domdt * s.t;
  nodem = nodem + s.dnodt * s.t;
  mm = mm + s.dmdt * s.t;

  var ft = 0.0;
  if (s.irez != 0) {
    if (atime == 0.0 || s.t * atime <= 0.0 || s.t.abs() < atime.abs()) {
      atime = 0.0;
      xni = no;
      xli = s.xlamo;
    }

    final delt = s.t > 0.0 ? stepp : stepn;

    var iretn = 381;
    var xndt = 0.0;
    var xldot = 0.0;
    var xnddt = 0.0;
    while (iretn == 381) {
      if (s.irez != 2) {
        xndt = s.del1 * math.sin(xli - fasx2) +
            s.del2 * math.sin(2.0 * (xli - fasx4)) +
            s.del3 * math.sin(3.0 * (xli - fasx6));
        xldot = xni + s.xfact;
        xnddt = s.del1 * math.cos(xli - fasx2) +
            2.0 * s.del2 * math.cos(2.0 * (xli - fasx4)) +
            3.0 * s.del3 * math.cos(3.0 * (xli - fasx6));
        xnddt = xnddt * xldot;
      } else {
        final xomi = argpo + argpdot * atime;
        final x2omi = xomi + xomi;
        final x2li = xli + xli;
        xndt = s.d2201 * math.sin(x2omi + xli - g22) +
            s.d2211 * math.sin(xli - g22) +
            s.d3210 * math.sin(xomi + xli - g32) +
            s.d3222 * math.sin(-xomi + xli - g32) +
            s.d4410 * math.sin(x2omi + x2li - g44) +
            s.d4422 * math.sin(x2li - g44) +
            s.d5220 * math.sin(xomi + xli - g52) +
            s.d5232 * math.sin(-xomi + xli - g52) +
            s.d5421 * math.sin(xomi + x2li - g54) +
            s.d5433 * math.sin(-xomi + x2li - g54);
        xldot = xni + s.xfact;
        xnddt = s.d2201 * math.cos(x2omi + xli - g22) +
            s.d2211 * math.cos(xli - g22) +
            s.d3210 * math.cos(xomi + xli - g32) +
            s.d3222 * math.cos(-xomi + xli - g32) +
            s.d5220 * math.cos(xomi + xli - g52) +
            s.d5232 * math.cos(-xomi + xli - g52) +
            2.0 *
                (s.d4410 * math.cos(x2omi + x2li - g44) +
                    s.d4422 * math.cos(x2li - g44) +
                    s.d5421 * math.cos(xomi + x2li - g54) +
                    s.d5433 * math.cos(-xomi + x2li - g54));
        xnddt = xnddt * xldot;
      }

      if ((s.t - atime).abs() >= stepp) {
        iretn = 381;
      } else {
        ft = s.t - atime;
        iretn = 0;
      }

      if (iretn == 381) {
        xli = xli + xldot * delt + xndt * step2;
        xni = xni + xndt * delt + xnddt * step2;
        atime = atime + delt;
      }
    }

    nm = xni + xndt * ft + xnddt * ft * ft * 0.5;
    final xl = xli + xldot * ft + xndt * ft * ft * 0.5;
    if (s.irez != 1) {
      mm = xl - 2.0 * nodem + 2.0 * theta;
      dndt = nm - no;
    } else {
      mm = xl - nodem - argpm + theta;
      dndt = nm - no;
    }
    nm = no + dndt;
  }

  return DspaceResult(
    atime: atime,
    em: em,
    argpm: argpm,
    inclm: inclm,
    xli: xli,
    mm: mm,
    xni: xni,
    nodem: nodem,
    dndt: dndt,
    nm: nm,
  );
}
