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

  group('quadraticPeak', () {
    test('finds the vertex of a symmetric parabola exactly', () {
      // f(t) = -(t - 5)^2 + 9, vertex at t = 5, value 9.
      double f(double t) => -(t - 5.0) * (t - 5.0) + 9.0;
      final est = quadraticPeak(
        t0: 3,
        t1: 5,
        t2: 7,
        f0: f(3),
        f1: f(5),
        f2: f(7),
      );
      expect(est.timeUs, closeTo(5.0, 1.0e-9));
      expect(est.value, closeTo(9.0, 1.0e-9));
    });

    test('finds an off-grid vertex of an asymmetric parabola', () {
      // Vertex not aligned with any sample: f(t) = -(t - 4.3)^2 + 12.
      double f(double t) => -(t - 4.3) * (t - 4.3) + 12.0;
      final est = quadraticPeak(
        t0: 2,
        t1: 5,
        t2: 8,
        f0: f(2),
        f1: f(5),
        f2: f(8),
      );
      expect(est.timeUs, closeTo(4.3, 1.0e-6));
      expect(est.value, closeTo(12.0, 1.0e-6));
    });

    test('clamps the vertex into the bracket and matches a sine peak', () {
      // A sine hump sampled around its peak: max of sin at t = pi/2.
      const peakT = math.pi / 2;
      double f(double t) => math.sin(t);
      final est = quadraticPeak(
        t0: peakT - 0.2,
        t1: peakT,
        t2: peakT + 0.2,
        f0: f(peakT - 0.2),
        f1: f(peakT),
        f2: f(peakT + 0.2),
      );
      // Quadratic fit near a smooth peak recovers it to high accuracy.
      expect(est.timeUs, closeTo(peakT, 1.0e-3));
      expect(est.value, closeTo(1.0, 1.0e-3));
      // Vertex stays inside the bracket.
      expect(est.timeUs, greaterThanOrEqualTo(peakT - 0.2));
      expect(est.timeUs, lessThanOrEqualTo(peakT + 0.2));
    });

    test('golden-section recovers a non-parabolic peak the fit would miss', () {
      // A sharply-peaked function (|sin|-like cusp) where a single quadratic
      // through 3 coarse samples under-reads the true maximum, but golden
      // section converges to it. Peak of cos^8 is at t = 0, value 1.
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

    test('golden-section finds a smooth parabola peak too', () {
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

    test('golden-section throws when cUs is not greater than aUs', () {
      double f(double t) => -t * t;
      expect(
        () => goldenSectionMax(f, aUs: 5, cUs: 5),
        throwsArgumentError,
      );
    });

    test('falls back to the middle sample for collinear points', () {
      // Straight line - no curvature, degenerate vertex.
      double f(double t) => 2.0 * t + 1.0;
      final est = quadraticPeak(
        t0: 0,
        t1: 1,
        t2: 2,
        f0: f(0),
        f1: f(1),
        f2: f(2),
      );
      expect(est.timeUs, 1.0);
      expect(est.value, f(1));
    });
  });
}
