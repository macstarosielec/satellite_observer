import 'dart:math' as math;

import 'package:satellite_observer/src/passes/root_refine.dart';
import 'package:test/test.dart';

void main() {
  group('bisectCrossing', () {
    test('finds the root of a monotonic linear function to sub-second', () {
      // Root at t = 1_000_000 us (1 s). f changes sign across it.
      const root = 1.0e6;
      double f(double t) => t - root;

      final got = bisectCrossing(
        f,
        loUs: 0,
        hiUs: 2000000,
        // Uses the default tolerance (1e5 us = 0.1 s).
      );
      // Within half the tolerance bracket of the true root.
      expect((got - root).abs(), lessThan(1.0e5));
    });

    test('converges to sub-microsecond with a tight tolerance', () {
      const root = 1234567.0;
      double f(double t) => t - root;
      final got = bisectCrossing(
        f,
        loUs: 0,
        hiUs: 5000000,
        toleranceUs: 1,
        maxIterations: 200,
      );
      expect((got - root).abs(), lessThan(1.0));
    });

    test('handles a downward (decreasing) crossing', () {
      const root = 3.0e6;
      double f(double t) => root - t; // positive below root, negative above
      final got = bisectCrossing(f, loUs: 0, hiUs: 6000000, toleranceUs: 1);
      expect((got - root).abs(), lessThan(1.0));
    });

    test('throws when endpoints do not bracket a sign change', () {
      double f(double t) => t + 1; // always positive over [0, 10]
      expect(
        () => bisectCrossing(f, loUs: 0, hiUs: 10),
        throwsArgumentError,
      );
    });

    test('throws when hiUs is not greater than loUs', () {
      double f(double t) => t;
      expect(
        () => bisectCrossing(f, loUs: 5, hiUs: 5),
        throwsArgumentError,
      );
    });

    test('returns an exact-zero endpoint', () {
      double f(double t) => t - 10.0;
      // hi endpoint is exactly the root.
      final got = bisectCrossing(f, loUs: 0, hiUs: 10);
      expect(got, closeTo(10.0, 1.0e-9));
    });
  });

  group('goldenSectionMax', () {
    test('recovers a non-parabolic peak a parabola fit would miss', () {
      // A sharply-peaked function (cos^8) where a single quadratic through 3
      // coarse samples under-reads the true maximum, but golden section
      // converges to it. Peak of cos^8 is at t = 0, value 1.
      double f(double t) => math.pow(math.cos(t), 8).toDouble();
      final est = goldenSectionMax(
        f,
        aUs: -0.6,
        cUs: 0.6,
        toleranceUs: 1.0e-6,
        maxIterations: 200,
      );
      expect(est.timeUs, closeTo(0.0, 1.0e-3));
      expect(est.value, closeTo(1.0, 1.0e-3));
    });

    test('finds a smooth parabola peak', () {
      double f(double t) => -(t - 4.3) * (t - 4.3) + 12.0;
      final est = goldenSectionMax(
        f,
        aUs: 2,
        cUs: 8,
        toleranceUs: 1.0e-6,
        maxIterations: 200,
      );
      expect(est.timeUs, closeTo(4.3, 1.0e-3));
      expect(est.value, closeTo(12.0, 1.0e-3));
    });

    test('throws when cUs is not greater than aUs', () {
      double f(double t) => -t * t;
      expect(
        () => goldenSectionMax(f, aUs: 5, cUs: 5),
        throwsArgumentError,
      );
    });
  });
}
