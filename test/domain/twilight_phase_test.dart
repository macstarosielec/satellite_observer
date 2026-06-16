import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

/// Unit checks for the [TwilightPhase] enum (ADR-7, FR-12).
void main() {
  group('TwilightPhase', () {
    test('carries the conventional Sun-altitude thresholds', () {
      // These are stored literals (not computed trig), so exact equality is
      // correct and portable.
      expect(TwilightPhase.civil.sunAltitudeDegrees, -6.0);
      expect(TwilightPhase.nautical.sunAltitudeDegrees, -12.0);
      expect(TwilightPhase.astronomical.sunAltitudeDegrees, -18.0);
    });

    test('exposes exactly the three documented phases', () {
      expect(
        TwilightPhase.values,
        [
          TwilightPhase.civil,
          TwilightPhase.nautical,
          TwilightPhase.astronomical,
        ],
      );
    });

    test('thresholds are strictly more negative for darker phases', () {
      expect(
        TwilightPhase.civil.sunAltitudeDegrees >
            TwilightPhase.nautical.sunAltitudeDegrees,
        isTrue,
      );
      expect(
        TwilightPhase.nautical.sunAltitudeDegrees >
            TwilightPhase.astronomical.sunAltitudeDegrees,
        isTrue,
      );
    });
  });
}
