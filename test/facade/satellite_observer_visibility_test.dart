import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

/// Facade-level L4 checks (FR-12/13/14, ADR-7): darkness enum-vs-raw parity,
/// known day/night verdicts, and argument validation.
///
/// Uses the same fixed ISS TLE + Warsaw observer as the visibility fixtures.
/// The chosen instants come straight from `sun_altitude_ref.json` /
/// `iss_visibility_ref.json` so the day/night classification is grounded in the
/// independent Skyfield reference, not hand-asserted.
void main() {
  // Warsaw, same as the fixtures.
  final observer = Observer(
    latitudeDeg: 52.2297,
    longitudeDeg: 21.0122,
    altitudeMeters: 100,
  );
  const tleL1 =
      '1 25544U 98067A   24122.51736111  .00016717  00000-0  30074-3 0  9991';
  const tleL2 =
      '2 25544  51.6406 211.0067 0004572  86.8242 273.3318 15.50186571 12345';

  final sat = SatelliteObserver(
    elements: GpElements.fromTle(tleL1, tleL2, name: 'ISS (ZARYA)'),
    observer: observer,
  );

  // Known instants (UTC) over Warsaw on 2024-05-02, per the Skyfield fixtures:
  //  * deep night: Sun ~ -15 deg (the evening pass instant).
  //  * full day:   Sun ~ +10 deg (the daytime pass instant).
  final nightInstant = DateTime.utc(2024, 5, 2, 1, 5);
  final dayInstant = DateTime.utc(2024, 5, 2, 4, 18);

  group('isObserverInDarkness (FR-12)', () {
    test('enum civil equals raw -6 at the same instant (parity)', () {
      // The headline FR-12 parity: the enum path and the raw escape hatch must
      // agree when given the same threshold, at several instants.
      final instants = <DateTime>[
        nightInstant,
        dayInstant,
        DateTime.utc(2024, 5, 2, 2, 30),
        DateTime.utc(2024, 5, 2, 3, 30),
        DateTime.utc(2024, 5, 1, 23, 45),
      ];
      for (final t in instants) {
        final viaEnum = sat.isObserverInDarkness(t);
        final viaRaw = sat.isObserverInDarkness(t, sunAltitudeBelowDeg: -6);
        expect(
          viaEnum,
          viaRaw,
          reason: 'enum civil (default) and raw -6 must agree at $t',
        );
      }
    });

    test('a known daytime instant is not dark for any phase', () {
      // Sun well above the horizon (~+10 deg): brighter than every threshold.
      expect(sat.isObserverInDarkness(dayInstant), isFalse);
      expect(
        sat.isObserverInDarkness(dayInstant, twilight: TwilightPhase.nautical),
        isFalse,
      );
      expect(
        sat.isObserverInDarkness(
          dayInstant,
          twilight: TwilightPhase.astronomical,
        ),
        isFalse,
      );
    });

    test('a known deep-night instant is dark for all three phases', () {
      // Sun ~ -15 deg: below civil (-6) and nautical (-12), but NOT below
      // astronomical (-18). So civil and nautical are dark; astronomical is
      // not. Assert each against its own threshold honestly.
      expect(sat.isObserverInDarkness(nightInstant), isTrue);
      expect(
        sat.isObserverInDarkness(
          nightInstant,
          twilight: TwilightPhase.nautical,
        ),
        isTrue,
      );
      // -15 is above -18, so astronomical darkness has NOT yet been reached.
      expect(
        sat.isObserverInDarkness(
          nightInstant,
          twilight: TwilightPhase.astronomical,
        ),
        isFalse,
      );

      // A genuinely deep-night instant (local solar midnight ~ 23:00 UTC) is
      // dark even by the strictest astronomical phase.
      final deepNight = DateTime.utc(2024, 5, 2, 23);
      expect(sat.isObserverInDarkness(deepNight), isTrue);
      expect(
        sat.isObserverInDarkness(deepNight, twilight: TwilightPhase.nautical),
        isTrue,
      );
      expect(
        sat.isObserverInDarkness(
          deepNight,
          twilight: TwilightPhase.astronomical,
        ),
        isTrue,
      );
    });

    test('raw threshold overrides the enum when both are given', () {
      // At the -15 deg instant: civil (-6) would say dark, but a raw threshold
      // of -18 (stricter) must say NOT dark, proving the raw value wins.
      expect(
        sat.isObserverInDarkness(nightInstant, sunAltitudeBelowDeg: -18),
        isFalse,
      );
    });

    test('normalises non-UTC input (ADR-13)', () {
      final utc = dayInstant;
      final local = utc.toLocal();
      expect(
        sat.isObserverInDarkness(local),
        sat.isObserverInDarkness(utc),
      );
    });
  });

  group('polar day/night darkness (FR-12 extremes)', () {
    // A high-Arctic observer (Svalbard, 78 N) exercises the twilight path at
    // the latitudes the single mid-latitude Warsaw fixture cannot reach: near
    // the summer solstice the Sun never sets (midnight sun -> never dark), and
    // near the winter solstice it never rises above the civil threshold
    // (polar night -> always dark). This is self-consistent physics; no
    // Skyfield reference needed. The satellite identity is irrelevant here -
    // isObserverInDarkness depends only on the observer and the Sun.
    final svalbard = Observer(
      latitudeDeg: 78,
      longitudeDeg: 15,
    );
    final polarSat = SatelliteObserver(
      elements: GpElements.fromTle(tleL1, tleL2, name: 'ISS (ZARYA)'),
      observer: svalbard,
    );

    test('midnight sun: never dark across a 24 h summer-solstice sweep', () {
      // 2024 June solstice ~ 21 Jun; the Sun stays above the civil threshold
      // all "night" at 78 N.
      for (var hour = 0; hour < 24; hour++) {
        final t = DateTime.utc(2024, 6, 21, hour);
        expect(
          polarSat.isObserverInDarkness(t),
          isFalse,
          reason: 'midnight sun: must NOT be dark (civil) at $t',
        );
      }
    });

    test('polar night: always dark across a 24 h winter-solstice sweep', () {
      // 2024 December solstice ~ 21 Dec; the Sun stays below the civil
      // threshold all day at 78 N.
      for (var hour = 0; hour < 24; hour++) {
        final t = DateTime.utc(2024, 12, 21, hour);
        expect(
          polarSat.isObserverInDarkness(t),
          isTrue,
          reason: 'polar night: must be dark (civil) at $t',
        );
      }
    });
  });

  group('twilight monotonicity through visiblePasses (ADR-7)', () {
    // Requiring DEEPER darkness can never ADD visible time: for the same
    // window, a darker phase (astronomical, -18) must yield a visible-interval
    // total that is a subset-or-equal of the civil (-6) total. Self-consistent
    // physics (darker threshold => fewer or equal dark samples => <= visible
    // time); seconds-based comparison, no Skyfield reference.
    test('astronomical visible-time <= civil visible-time over a window', () {
      final from = DateTime.utc(2024, 5, 1, 18);
      final to = DateTime.utc(2024, 5, 2, 6);

      double totalVisibleSeconds(TwilightPhase phase) {
        final results = sat.visiblePasses(from: from, to: to, twilight: phase);
        var seconds = 0.0;
        for (final pv in results) {
          for (final iv in pv.visibleIntervals) {
            seconds +=
                iv.endUtc.difference(iv.startUtc).inMicroseconds.abs() / 1e6;
          }
        }
        return seconds;
      }

      final civilSeconds = totalVisibleSeconds(TwilightPhase.civil);
      final astroSeconds = totalVisibleSeconds(TwilightPhase.astronomical);

      // Small guard band (1 s) for edge-bisection jitter at the boundaries.
      expect(
        astroSeconds,
        lessThanOrEqualTo(civilSeconds + 1.0),
        reason: 'deeper darkness (astronomical) must not add visible time '
            'vs civil: astro=$astroSeconds s, civil=$civilSeconds s',
      );
    });
  });

  group('visiblePasses argument validation', () {
    test('throws when from is not before to', () {
      final t = DateTime.utc(2024, 5, 2, 1);
      expect(
        () => sat.visiblePasses(from: t, to: t),
        throwsArgumentError,
      );
    });

    test('throws when minElevationDeg is out of [0, 90)', () {
      final from = DateTime.utc(2024, 5, 2);
      final to = DateTime.utc(2024, 5, 2, 6);
      expect(
        () => sat.visiblePasses(from: from, to: to, minElevationDeg: -1),
        throwsArgumentError,
      );
      expect(
        () => sat.visiblePasses(from: from, to: to, minElevationDeg: 90),
        throwsArgumentError,
      );
    });
  });

  group('nextVisiblePass argument validation', () {
    test('throws when within is not positive', () {
      expect(
        () => sat.nextVisiblePass(
          after: DateTime.utc(2024, 5, 2),
          within: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('throws when minElevationDeg is out of range', () {
      expect(
        () => sat.nextVisiblePass(
          after: DateTime.utc(2024, 5, 2),
          minElevationDeg: 90,
        ),
        throwsArgumentError,
      );
    });
  });
}
