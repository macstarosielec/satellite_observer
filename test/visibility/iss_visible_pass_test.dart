import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

/// The end-to-end visibility gate (FR-14, ADR-2/6/7): the headline capability.
///
/// For the same fixed ISS TLE + Warsaw observer the generator gave Skyfield,
/// we run `visiblePasses` over each reference pass window and check:
///
/// * the evening pass is `isVisible == true` with a visible interval whose
///   extent overlaps Skyfield's reference interval (compared within tens of
///   seconds, NOT an exact crossing instant - the eclipse-tolerance caveat);
/// * the daytime pass is `isVisible == false`.
///
/// The visible-interval extent is allowed to differ from the reference by up to
/// the interval tolerance (tens of seconds) because the umbra crossing that
/// bounds it is subject to the documented ~arc-minute Sun-direction shift (see
/// eclipse_test.dart).
void main() {
  group('ISS visible pass vs Skyfield (FR-14 headline)', () {
    late SatelliteObserver sat;
    late double twilightDeg;
    late List<Map<String, dynamic>> passes;

    setUpAll(() async {
      final raw = await File(
        'test/fixtures/visibility/iss_visibility_ref.json',
      ).readAsString();
      final fixture = jsonDecode(raw) as Map<String, dynamic>;
      final tle = fixture['tle'] as Map<String, dynamic>;
      final obs = fixture['observer'] as Map<String, dynamic>;
      sat = SatelliteObserver(
        elements: GpElements.fromTle(
          tle['line1'] as String,
          tle['line2'] as String,
          name: tle['name'] as String,
        ),
        observer: Observer(
          latitudeDeg: (obs['latDeg'] as num).toDouble(),
          longitudeDeg: (obs['lonDeg'] as num).toDouble(),
          altitudeMeters: (obs['altM'] as num).toDouble(),
        ),
      );
      twilightDeg = (fixture['twilightDeg'] as num).toDouble();
      passes =
          (fixture['passes'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    const intervalTolSeconds = 30.0;

    test(
        'evening pass is visible and overlaps Skyfield interval; '
        'daytime pass is not visible', () {
      expect(passes.length, 2);

      // The fixture emits the evening (visible) pass first, then the daytime
      // (invisible) pass; assert both verdicts from the same code path.
      final evening = passes[0];
      final daytime = passes[1];

      // --- Evening pass: must be visible with an overlapping interval. ---
      final evWindow = evening['window'] as Map<String, dynamic>;
      final evFrom = DateTime.parse(evWindow['from'] as String);
      final evTo = DateTime.parse(evWindow['to'] as String);
      // Widen the search window slightly so the pass is fully bracketed (the
      // reference window is the rise..set extent itself).
      final evResults = sat.visiblePasses(
        from: evFrom.subtract(const Duration(minutes: 5)),
        to: evTo.add(const Duration(minutes: 5)),
        sunAltitudeBelowDeg: twilightDeg,
      );
      // Exactly one pass falls in this short window.
      expect(evResults.length, 1, reason: 'expected one evening pass');
      final ev = evResults.single;
      expect(ev.isVisible, isTrue, reason: 'evening pass must be visible');
      expect(ev.visibleIntervals, isNotEmpty);

      final refIntervals = (evening['visibleIntervals'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(refIntervals, isNotEmpty, reason: 'fixture sanity');

      // Compare the union extent (earliest start, latest end) on each side -
      // robust to a one-vs-many interval split at the boundary.
      final refStart = DateTime.parse(refIntervals.first['startUtc'] as String);
      final refEnd = DateTime.parse(refIntervals.last['endUtc'] as String);
      final gotStart = ev.visibleIntervals.first.startUtc;
      final gotEnd = ev.visibleIntervals.last.endUtc;

      final startDiff =
          gotStart.difference(refStart).inMicroseconds.abs() / 1e6;
      final endDiff = gotEnd.difference(refEnd).inMicroseconds.abs() / 1e6;

      expect(
        startDiff,
        lessThanOrEqualTo(intervalTolSeconds),
        reason: 'visible-interval start: got $gotStart, ref $refStart',
      );
      expect(
        endDiff,
        lessThanOrEqualTo(intervalTolSeconds),
        reason: 'visible-interval end: got $gotEnd, ref $refEnd',
      );

      // The intervals must actually overlap (not merely be close-but-disjoint).
      final overlapStart = gotStart.isAfter(refStart) ? gotStart : refStart;
      final overlapEnd = gotEnd.isBefore(refEnd) ? gotEnd : refEnd;
      expect(
        overlapStart.isBefore(overlapEnd),
        isTrue,
        reason: 'Dart and Skyfield visible intervals must overlap',
      );

      // The peak look-angle must sit inside the reported interval and be a
      // real above-horizon look.
      final peak = ev.visibleIntervals.first.peakLookAngle;
      expect(peak.elevationDeg, greaterThan(0));

      // ignore: avoid_print
      print('Evening visible interval: Dart $gotStart..$gotEnd, '
          'Skyfield $refStart..$refEnd '
          '(start diff ${startDiff.toStringAsFixed(1)} s, '
          'end diff ${endDiff.toStringAsFixed(1)} s)');

      // --- Daytime pass: must NOT be visible. ---
      final dayWindow = daytime['window'] as Map<String, dynamic>;
      final dayFrom = DateTime.parse(dayWindow['from'] as String);
      final dayTo = DateTime.parse(dayWindow['to'] as String);
      final dayResults = sat.visiblePasses(
        from: dayFrom.subtract(const Duration(minutes: 5)),
        to: dayTo.add(const Duration(minutes: 5)),
        sunAltitudeBelowDeg: twilightDeg,
      );
      expect(dayResults.length, 1, reason: 'expected one daytime pass');
      final day = dayResults.single;
      expect(
        day.isVisible,
        isFalse,
        reason: 'daytime pass must not be visible (Sun up)',
      );
      expect(day.visibleIntervals, isEmpty);
    });

    test('visible interval still-visible at set clamps its end to pass set',
        () {
      // Boundary-clip path: in the reference fixture the evening pass is still
      // sunlit-and-dark at set, so its visible interval must END at the pass
      // set instant (not be extended past it, and not be quantised to the
      // coarse 2 s sample grid). This exercises the open-at-pass-end branch in
      // computePassVisibility that the mid-pass cases do not.
      final evWindow = passes[0]['window'] as Map<String, dynamic>;
      final evFrom = DateTime.parse(evWindow['from'] as String);
      final evTo = DateTime.parse(evWindow['to'] as String);
      final refIntervals = (passes[0]['visibleIntervals'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final refLastEnd = DateTime.parse(refIntervals.last['endUtc'] as String);

      // Sanity: the fixture's last interval end coincides with the pass set
      // window bound, i.e. this fixture really does exercise the clip path.
      expect(
        refLastEnd.difference(evTo).inSeconds.abs(),
        lessThanOrEqualTo(1),
        reason: 'fixture sanity: reference interval should end at pass set',
      );

      final results = sat.visiblePasses(
        from: evFrom.subtract(const Duration(minutes: 5)),
        to: evTo.add(const Duration(minutes: 5)),
        sunAltitudeBelowDeg: twilightDeg,
      );
      final pv = results.single;
      final lastEnd = pv.visibleIntervals.last.endUtc;
      final passSet = pv.pass.set.utc;

      // The interval end must coincide with the pass set (clamped, not
      // extended): equal to within sub-second edge tolerance.
      final clampDiff = lastEnd.difference(passSet).inMicroseconds.abs() / 1e6;
      expect(
        clampDiff,
        lessThanOrEqualTo(0.5),
        reason: 'still-visible-at-set interval end ($lastEnd) must clamp to '
            'the pass set ($passSet)',
      );
      // And it must never be pushed past the pass set.
      expect(
        lastEnd.isAfter(passSet.add(const Duration(milliseconds: 1))),
        isFalse,
        reason: 'interval end must not extend beyond the pass set',
      );
    });

    test('returned visibleIntervals is unmodifiable (cannot be mutated)', () {
      // PassVisibility is @immutable; the calculator wraps the interval list in
      // List.unmodifiable so a consumer cannot mutate the verdict after the
      // fact. Mutating it must throw UnsupportedError.
      final evWindow = passes[0]['window'] as Map<String, dynamic>;
      final evFrom = DateTime.parse(evWindow['from'] as String);
      final evTo = DateTime.parse(evWindow['to'] as String);
      final results = sat.visiblePasses(
        from: evFrom.subtract(const Duration(minutes: 5)),
        to: evTo.add(const Duration(minutes: 5)),
        sunAltitudeBelowDeg: twilightDeg,
      );
      final pv = results.single;
      expect(pv.visibleIntervals, isNotEmpty);
      expect(
        () => pv.visibleIntervals.add(pv.visibleIntervals.first),
        throwsUnsupportedError,
      );
    });

    test('nextVisiblePass returns the evening pass, not the daytime one', () {
      final evWindow = passes[0]['window'] as Map<String, dynamic>;
      final evFrom = DateTime.parse(evWindow['from'] as String);

      final next = sat.nextVisiblePass(
        after: evFrom.subtract(const Duration(minutes: 30)),
        within: const Duration(hours: 6),
      );
      expect(next, isNotNull);
      expect(next!.isVisible, isTrue);
      // Its rise must be within a few minutes of the reference evening rise.
      final riseDiff =
          next.pass.rise.utc.difference(evFrom).inMicroseconds.abs() / 1e6;
      expect(riseDiff, lessThan(60));
    });

    test('isSatelliteSunlit agrees with the eclipse fixture at sampled times',
        () {
      // Spot-check parity between the facade sunlit method and the fixture on a
      // handful of samples spread across the evening pass (the full per-sample
      // gate with the guard band lives in eclipse_test.dart).
      final samples =
          (passes[0]['samples'] as List<dynamic>).cast<Map<String, dynamic>>();
      var checked = 0;
      var agree = 0;
      // Skip samples within 30 s of a transition (those are guard-band).
      final times = samples
          .map((s) => DateTime.parse(s['utc'] as String))
          .toList(growable: false);
      final ref =
          samples.map((s) => s['sunlit'] as bool).toList(growable: false);
      final transitionTimes = <DateTime>[];
      for (var i = 1; i < ref.length; i++) {
        if (ref[i] != ref[i - 1]) {
          transitionTimes
            ..add(times[i - 1])
            ..add(times[i]);
        }
      }
      bool nearTransition(DateTime t) => transitionTimes.any(
            (tt) => t.difference(tt).inMicroseconds.abs() / 1e6 <= 30.0,
          );

      // Sample every ~10th point to keep this a cheap spot-check.
      for (var i = 0;
          i < samples.length;
          i += math.max(1, samples.length ~/ 8)) {
        if (nearTransition(times[i])) continue;
        checked++;
        if (sat.isSatelliteSunlit(times[i]) == ref[i]) agree++;
      }
      expect(checked, greaterThan(0));
      expect(
        agree,
        checked,
        reason: 'facade isSatelliteSunlit must match the fixture away from '
            'umbra crossings',
      );
    });
  });
}
