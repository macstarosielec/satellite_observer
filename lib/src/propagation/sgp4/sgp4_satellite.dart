// This is a library-internal mutable record (never exported from the public
// barrel). Its fields mirror Vallado's flat `satrec` struct one-to-one, so we
// opt out of member-doc and int-literal lints for this single file rather than
// document ~100 scratch coefficients or diverge from the reference's 0.0
// defaults.
// ignore_for_file: public_member_api_docs, prefer_int_literals

import 'package:satellite_observer/src/propagation/sgp4/gravity_constants.dart';

/// Mutable internal SGP4 satellite record (mirrors Vallado's `satrec`).
///
/// Holds every coefficient produced by `sgp4init` plus the singly-averaged
/// mean elements updated by the propagation step. This is library-private
/// state; consumers never see it.
///
/// Ported from the MIT-licensed python-sgp4 (Brandon Rhodes); see
/// Vallado, Crawford, Hujsak, Kelso, "Revisiting Spacetrack Report #3",
/// AIAA 2006-6753.
class Sgp4Satellite {
  /// Creates a record bound to the given gravity [constants].
  Sgp4Satellite(this.constants);

  /// Gravity constants in effect for this satellite.
  final GravityConstants constants;

  // ---- Operation mode and bookkeeping. ----
  String operationmode = 'i';
  String init = 'y';
  String method = 'n';
  int error = 0;

  // ---- Epoch (days from 1950 Jan 0.0). ----
  double epochDays1950 = 0.0;

  // ---- Input mean elements (radians, rad/min). ----
  double bstar = 0.0;
  double ndot = 0.0;
  double nddot = 0.0;
  double ecco = 0.0;
  double argpo = 0.0;
  double inclo = 0.0;
  double mo = 0.0;
  double noKozai = 0.0;
  double nodeo = 0.0;

  // ---- Near-earth coefficients. ----
  int isimp = 0;
  double aycof = 0.0;
  double con41 = 0.0;
  double cc1 = 0.0;
  double cc4 = 0.0;
  double cc5 = 0.0;
  double d2 = 0.0;
  double d3 = 0.0;
  double d4 = 0.0;
  double delmo = 0.0;
  double eta = 0.0;
  double argpdot = 0.0;
  double omgcof = 0.0;
  double sinmao = 0.0;
  double t = 0.0;
  double t2cof = 0.0;
  double t3cof = 0.0;
  double t4cof = 0.0;
  double t5cof = 0.0;
  double x1mth2 = 0.0;
  double x7thm1 = 0.0;
  double mdot = 0.0;
  double nodedot = 0.0;
  double xlcof = 0.0;
  double xmcof = 0.0;
  double nodecf = 0.0;

  // ---- Derived quantities. ----
  double noUnkozai = 0.0;
  double a = 0.0;
  double alta = 0.0;
  double altp = 0.0;
  double gsto = 0.0;

  // ---- Deep-space coefficients. ----
  int irez = 0;
  double d2201 = 0.0;
  double d2211 = 0.0;
  double d3210 = 0.0;
  double d3222 = 0.0;
  double d4410 = 0.0;
  double d4422 = 0.0;
  double d5220 = 0.0;
  double d5232 = 0.0;
  double d5421 = 0.0;
  double d5433 = 0.0;
  double dedt = 0.0;
  double del1 = 0.0;
  double del2 = 0.0;
  double del3 = 0.0;
  double didt = 0.0;
  double dmdt = 0.0;
  double dnodt = 0.0;
  double domdt = 0.0;
  double e3 = 0.0;
  double ee2 = 0.0;
  double peo = 0.0;
  double pgho = 0.0;
  double pho = 0.0;
  double pinco = 0.0;
  double plo = 0.0;
  double se2 = 0.0;
  double se3 = 0.0;
  double sgh2 = 0.0;
  double sgh3 = 0.0;
  double sgh4 = 0.0;
  double sh2 = 0.0;
  double sh3 = 0.0;
  double si2 = 0.0;
  double si3 = 0.0;
  double sl2 = 0.0;
  double sl3 = 0.0;
  double sl4 = 0.0;
  double xfact = 0.0;
  double xgh2 = 0.0;
  double xgh3 = 0.0;
  double xgh4 = 0.0;
  double xh2 = 0.0;
  double xh3 = 0.0;
  double xi2 = 0.0;
  double xi3 = 0.0;
  double xl2 = 0.0;
  double xl3 = 0.0;
  double xl4 = 0.0;
  double xlamo = 0.0;
  double zmol = 0.0;
  double zmos = 0.0;
  double atime = 0.0;
  double xli = 0.0;
  double xni = 0.0;

  // ---- Singly-averaged mean elements (set each propagation step). ----
  double am = 0.0;
  double em = 0.0;
  double im = 0.0;
  double bigOm = 0.0;
  double om = 0.0;
  double mm = 0.0;
  double nm = 0.0;
}
