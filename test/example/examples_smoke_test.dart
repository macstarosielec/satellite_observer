/// Offline smoke test for the runnable examples.
///
/// This exercises the SAME offline construction the `example/` programs use
/// (the committed ISS TLE, the Warsaw observer, and the fixed windows/instants
/// near the TLE epoch) and asserts no-throw plus plausible values. It guards
/// that the example logic stays runnable offline as the library evolves.
///
/// It does NOT shell out to `dart run`; it calls the public API directly so the
/// assertions are precise and CI-fast. The live `fetch_with_celestrak.dart`
/// example is intentionally not covered here (it needs network).
library;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

// The committed ISS (ZARYA) TLE used by every offline example. Epoch is
// 2024 day 122 (2024-05-01 UTC).
const _issLine1 =
    '1 25544U 98067A   24122.51736111  .00016717  00000-0  30074-3 0  9991';
const _issLine2 =
    '2 25544  51.6406 211.0067 0004572  86.8242 273.3318 15.50186571 12345';

SatelliteObserver _buildExampleObserver() => SatelliteObserver(
      elements: GpElements.fromTle(_issLine1, _issLine2, name: 'ISS (ZARYA)'),
      observer: Observer(
        latitudeDeg: 52.2297,
        longitudeDeg: 21.0122,
        altitudeMeters: 100,
      ),
    );

void main() {
  group('examples run offline against the committed TLE', () {
    late SatelliteObserver iss;

    setUp(() {
      iss = _buildExampleObserver();
    });

    test('construction from the committed TLE does not throw', () {
      expect(_buildExampleObserver, returnsNormally);
      expect(iss.epoch.year, 2024);
    });

    test('look_angle.dart: lookAngleAt yields plausible angles', () {
      final at = DateTime.utc(2024, 5, 2, 2, 41, 5);
      late final LookAngle look;
      expect(() => look = iss.lookAngleAt(at), returnsNormally);

      expect(look.azimuthDeg, inInclusiveRange(0, 360));
      expect(look.azimuthDeg, lessThan(360)); // half-open [0, 360)
      expect(look.elevationDeg, inInclusiveRange(-90, 90));
      expect(look.rangeKm, greaterThan(0));
      expect(look.rangeKm.isFinite, isTrue);
      expect(look.rangeRateKmS.isFinite, isTrue);
    });

    test('look_angle.dart: subPointAt yields plausible coordinates', () {
      final at = DateTime.utc(2024, 5, 2, 2, 41, 5);
      late final SubSatellitePoint sub;
      expect(() => sub = iss.subPointAt(at), returnsNormally);

      expect(sub.latitudeDeg, inInclusiveRange(-90, 90));
      expect(sub.longitudeDeg, inInclusiveRange(-180, 180));
      expect(sub.altitudeKm, greaterThan(200)); // LEO ISS altitude band
      expect(sub.altitudeKm, lessThan(600));
    });

    test('passes.dart: a multi-day window yields at least one pass', () {
      final from = DateTime.utc(2024, 5, 1, 12, 25);
      final to = DateTime.utc(2024, 5, 4, 12, 25);
      late final List<Pass> found;
      expect(() => found = iss.passes(from: from, to: to), returnsNormally);

      expect(found, isNotEmpty);
      for (final pass in found) {
        // Events are time-ordered.
        expect(
          pass.rise.utc.isAfter(pass.culmination.utc),
          isFalse,
          reason: 'rise must not be after culmination',
        );
        expect(
          pass.culmination.utc.isAfter(pass.set.utc),
          isFalse,
          reason: 'culmination must not be after set',
        );
        // Default horizon is 10 deg, so the peak must clear it.
        expect(pass.peakElevationDeg, greaterThanOrEqualTo(10));
        expect(pass.peakElevationDeg, lessThanOrEqualTo(90));
      }
    });

    test('visible_iss_pass.dart: nextVisiblePass finds a visible pass', () {
      final after = DateTime.utc(2024, 5, 1, 12);
      late final PassVisibility? visible;
      expect(
        () => visible = iss.nextVisiblePass(after: after),
        returnsNormally,
      );

      expect(visible, isNotNull);
      expect(visible!.isVisible, isTrue);
      expect(visible!.visibleIntervals, isNotEmpty);

      final interval = visible!.visibleIntervals.first;
      expect(
        interval.endUtc.isBefore(interval.startUtc),
        isFalse,
        reason: 'interval end must not precede its start',
      );
      final peak = interval.peakLookAngle;
      expect(peak.azimuthDeg, inInclusiveRange(0, 360));
      expect(peak.azimuthDeg, lessThan(360));
      expect(peak.elevationDeg, inInclusiveRange(-90, 90));
      expect(peak.rangeKm, greaterThan(0));
    });
  });
}
