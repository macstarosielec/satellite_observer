import 'dart:io';
import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';
// ignore: implementation_imports
// Reaches into src/ for Sgp4Result: the gate compares raw r/v vectors that are
// not surfaced through the public barrel.
import 'package:satellite_observer/src/propagation/sgp4/sgp4_core.dart';
// ignore: implementation_imports
// Reaches into src/ for the internal tsince-based propagate seam
// (propagateTsinceForTesting), which the gate feeds tsince directly to match
// python-sgp4's sgp4_tsince without DateTime round-trip error.
import 'package:satellite_observer/src/propagation/sgp4/sgp4_engine.dart';
import 'package:test/test.dart';

// Canonical SGP4 verification gate.
//
// Mirrors python-sgp4's run_satellite_against_tcppver /
// generate_satellite_output. Each satellite in SGP4-VER.TLE is propagated at
// every tsince emitted in tcppver.out, and the first 7 fields (tsince, x, y,
// z, xdot, ydot, zdot) are compared against the reference. The remaining
// orbital-element columns are NOT reproduced (they derive from rv2coe, which
// this library does not provide); the r/v comparison fully exercises the
// propagator.
//
// TLE string literals below are exactly 69 columns and cannot be wrapped, so
// the line-length lint is relaxed for this file.
// ignore_for_file: lines_longer_than_80_chars
//
// Tolerance: a faithful float64 port reproduces Vallado's vectors to well below
// python-sgp4's printed-field bound of error = 2e-7. We assert position within
// 1e-6 km and velocity within 1e-9 km/s; both are tighter than 2e-7 on the
// printed magnitudes yet comfortably met by a correct port. We do NOT loosen
// these to mask error - any real discrepancy must be fixed in the engine.
const double _posTolKm = 1e-6;
const double _velTolKmS = 1e-9;

// Deep-space cutoff: orbital period >= 225 minutes -> SDP4 (per ADR-14).
const double _deepSpacePeriodMin = 225;

/// One expected sample row from tcppver.out.
class _Row {
  _Row(this.tsince, this.x, this.y, this.z, this.xdot, this.ydot, this.zdot);

  final double tsince;
  final double x;
  final double y;
  final double z;
  final double xdot;
  final double ydot;
  final double zdot;
}

/// One satellite block: its TLE, the expected rows, the step, and (if the
/// reference stopped early) the expected SGP4 error code at the next step.
class _Case {
  _Case({
    required this.satnum,
    required this.line1,
    required this.line2,
    required this.rows,
    required this.tstep,
    required this.expectedErrorCode,
    required this.periodMinutes,
  });

  final String satnum;
  final String line1;
  final String line2;
  final List<_Row> rows;
  final double tstep;
  final int? expectedErrorCode;
  final double periodMinutes;

  bool get isDeepSpace => periodMinutes >= _deepSpacePeriodMin;
}

List<_Case> _loadCases() {
  final dir = _fixtureDir();
  final tleLines = File('$dir/SGP4-VER.TLE')
      .readAsStringSync()
      .replaceAll('\r', '')
      .split('\n');
  final outText =
      File('$dir/tcppver.out').readAsStringSync().replaceAll('\r', '');

  // Parse the TLE file into ordered (line1, line2, start, stop, step) entries.
  final tles = <Map<String, Object>>[];
  String? l1;
  for (final raw in tleLines) {
    if (raw.startsWith('1 ')) {
      l1 = raw;
    } else if (raw.startsWith('2 ') && l1 != null) {
      final extra = raw.length > 69
          ? raw.substring(69).trim().split(RegExp(r'\s+'))
          : <String>[];
      tles.add({
        'satnum': l1.substring(2, 7).trim(),
        'line1': l1,
        'line2': raw,
        'tstep': extra.length >= 3 ? double.parse(extra[2]) : 0.0,
        'tstop': extra.length >= 3 ? double.parse(extra[1]) : 0.0,
      });
      l1 = null;
    }
  }

  // Parse tcppver.out into blocks of data rows keyed by header order.
  final blocks = <List<_Row>>[];
  List<_Row>? cur;
  for (final raw in outText.split('\n')) {
    if (raw.contains(' xx')) {
      cur = <_Row>[];
      blocks.add(cur);
    } else if (raw.trim().isEmpty) {
      continue;
    } else if (cur != null) {
      final f = raw.trim().split(RegExp(r'\s+'));
      if (f.length < 7) continue;
      cur.add(
        _Row(
          double.parse(f[0]),
          double.parse(f[1]),
          double.parse(f[2]),
          double.parse(f[3]),
          double.parse(f[4]),
          double.parse(f[5]),
          double.parse(f[6]),
        ),
      );
    }
  }

  if (blocks.length != tles.length) {
    throw StateError(
      'TLE count ${tles.length} != tcppver.out block count ${blocks.length}',
    );
  }

  // The expected SGP4 error codes for the satellites whose reference output
  // stops before tstop, in TLE order. Matches python-sgp4 tests.py:
  // run_satellite_against_tcppver(..., [1, 1, 6, 6, 4, 3, 6]).
  const errorCodes = <int>[1, 1, 6, 6, 4, 3, 6];

  final cases = <_Case>[];
  var errIdx = 0;
  for (var i = 0; i < tles.length; i++) {
    final t = tles[i];
    final rows = blocks[i];
    final tstop = t['tstop']! as double;
    final tstep = t['tstep']! as double;
    final lastT = rows.last.tsince;
    final endedEarly = (lastT - tstop).abs() > 1e-6;

    int? expectedError;
    if (endedEarly) {
      expectedError = errorCodes[errIdx];
      errIdx++;
    }

    final el = GpElements.fromTle(t['line1']! as String, t['line2']! as String);
    final periodMin = 2.0 * math.pi / el.meanMotionRadPerMin;

    cases.add(
      _Case(
        satnum: t['satnum']! as String,
        line1: t['line1']! as String,
        line2: t['line2']! as String,
        rows: rows,
        tstep: tstep,
        expectedErrorCode: expectedError,
        periodMinutes: periodMin,
      ),
    );
  }

  if (errIdx != errorCodes.length) {
    throw StateError(
      'early-stopping satellites $errIdx != error list ${errorCodes.length}',
    );
  }

  return cases;
}

String _fixtureDir() {
  // Tests run from the package root.
  return 'test/fixtures/vallado';
}

void _runCase(_Case c) {
  final el = GpElements.fromTle(c.line1, c.line2, name: c.satnum);
  final engine = Sgp4Engine(el);

  // Match every emitted row. For error satellites the propagation may raise at
  // (or before) the point where the reference generator stopped - including at
  // t=0, where the modern algorithm supersedes a stale C++ row left in the
  // fixture (catalog 33334). Once a raise occurs at an expected-error
  // satellite, stop matching the remaining (artifact) rows and verify the code.
  int? caughtCode;
  for (final row in c.rows) {
    if (c.expectedErrorCode != null) {
      try {
        final result = propagateTsinceForTesting(engine, row.tsince);
        expect(
          result.error,
          0,
          reason: 'sat ${c.satnum} t=${row.tsince}: expected success',
        );
        _expectClose(result, row, c.satnum);
      } on PropagationException catch (e) {
        caughtCode = e.code;
        break;
      }
    } else {
      final result = propagateTsinceForTesting(engine, row.tsince);
      expect(
        result.error,
        0,
        reason: 'sat ${c.satnum} t=${row.tsince}: expected success',
      );
      _expectClose(result, row, c.satnum);
    }
  }

  if (c.expectedErrorCode != null) {
    // The loop above breaks (leaving caughtCode set) as soon as the expected
    // error is raised within the emitted rows. If it never raised there, the
    // reference generator must have stopped exactly one step past the last
    // emitted row, so we probe that step below. Together the loop + probe
    // guarantee caughtCode is populated before the final assertion, so a
    // satellite that silently never errors fails the `equals` check rather
    // than passing unnoticed.
    if (caughtCode == null) {
      final nextT = c.rows.last.tsince + c.tstep;
      try {
        propagateTsinceForTesting(engine, nextT);
      } on PropagationException catch (e) {
        caughtCode = e.code;
      }
    }
    expect(
      caughtCode,
      c.expectedErrorCode,
      reason: 'sat ${c.satnum}: expected SGP4 error ${c.expectedErrorCode}',
    );
  }
}

void _expectClose(Sgp4Result r, _Row e, String satnum) {
  void chk(double actual, double expected, String label) {
    final tol = label.startsWith('v') ? _velTolKmS : _posTolKm;
    expect(
      (actual - expected).abs(),
      lessThan(tol),
      reason: 'sat $satnum t=${e.tsince} $label: '
          'got $actual expected $expected (diff ${(actual - expected).abs()})',
    );
  }

  chk(r.position.x, e.x, 'x');
  chk(r.position.y, e.y, 'y');
  chk(r.position.z, e.z, 'z');
  chk(r.velocity.x, e.xdot, 'vx');
  chk(r.velocity.y, e.ydot, 'vy');
  chk(r.velocity.z, e.zdot, 'vz');
}

void main() {
  final cases = _loadCases();
  final nearEarth = cases.where((c) => !c.isDeepSpace).toList();
  final deepSpace = cases.where((c) => c.isDeepSpace).toList();

  group('Vallado SGP4-VER gate (near-earth, period < 225 min)', () {
    for (final c in nearEarth) {
      test('satellite ${c.satnum} (${c.rows.length} steps)', () {
        _runCase(c);
      });
    }
  });

  group('Vallado SGP4-VER gate (deep-space, period >= 225 min)', () {
    for (final c in deepSpace) {
      test('satellite ${c.satnum} (${c.rows.length} steps)', () {
        _runCase(c);
      });
    }
  });
}
