@Tags(['integration'])
library;

import 'dart:io' show Directory;

import 'package:celestrak/celestrak.dart';
import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

/// LIVE end-to-end smoke of the `celestrak` -> `satellite_observer` pipeline.
///
/// Unlike every other test in this package, this one is NOT offline: it hits
/// the real CelesTrak network API through the `celestrak` dev_dependency to
/// fetch TODAY's ISS (NORAD 25544) orbital elements, then feeds them straight
/// into the `satellite_observer` compute surface (propagation, look-angles,
/// sub-point, pass prediction, visibility).
///
/// It is tagged `integration` so it is EXCLUDED from the default `dart test`
/// run (the CI / offline suite stays network-free, NFR-4). Run it explicitly
/// with `dart test --tags integration`.
///
/// What it proves vs what it does NOT prove:
/// * Deterministic numerical correctness of the SGP4/look-angle/pass math is
///   already covered by the committed Vallado (`test/fixtures/vallado`) and
///   Skyfield (`test/fixtures/visibility`, `test/fixtures/passes`) golden
///   fixtures, which pin exact reference values against a frozen TLE.
/// * THIS test proves the live handoff works: the `SatelliteTle` that
///   `celestrak` returns over the wire parses cleanly into `GpElements` and the
///   full facade produces SANE output on whatever the current elements are.
///
/// Because live elements change daily, this file asserts SANE RANGES and
/// no-crash behaviour only - never exact equality on any computed double or
/// DateTime. A failure here means either the network is unreachable (the fetch
/// throws / no fresh TLE) or a genuine regression in the live handoff.
void main() {
  group('LIVE celestrak -> satellite_observer pipeline (ISS 25544)', () {
    // ISS NORAD catalog number.
    const issNoradId = 25544;

    // Warsaw, Poland - a mid-latitude site below the ISS inclination (~51.6
    // deg), so the ISS passes overhead several times a day.
    final warsaw = Observer(
      latitudeDeg: 52.2297,
      longitudeDeg: 21.0122,
      altitudeMeters: 100,
    );

    late Directory cacheDir;
    late CelestrakClient client;
    late SatelliteTle tle;
    late SatelliteObserver sat;
    // A single "now" instant shared by every assertion below so the snapshot
    // is internally consistent.
    late DateTime now;

    setUpAll(() async {
      cacheDir = await Directory.systemTemp.createTemp('celestrak_live_test_');
      client = CelestrakClient(cacheDir: cacheDir.path);

      // 1. LIVE fetch of the current ISS TLE over the network. If the network
      //    is unreachable this throws and the test fails loudly (we do NOT
      //    silently skip - "no network" must be visible when run with
      //    --tags integration).
      tle = await client.fetchByNoradId(issNoradId);

      now = DateTime.now().toUtc();

      // 2. Build the compute facade from the live elements.
      sat = SatelliteObserver(
        elements: GpElements.fromTle(tle.line1, tle.line2, name: tle.name),
        observer: warsaw,
      );

      // Surface what we actually fetched + computed, so the run log
      // demonstrates it really executed against live data.
      // ignore: avoid_print
      print('LIVE ISS TLE: name="${tle.name}" epoch=${tle.epoch} '
          'now=$now');
    });

    tearDownAll(() {
      client.dispose();
      if (cacheDir.existsSync()) {
        cacheDir.deleteSync(recursive: true);
      }
    });

    test('fetched TLE is fresh (epoch within ~30 days of now)', () {
      // A stale TLE would mean we did not really get current data. CelesTrak
      // refreshes the ISS several times a day, so 30 days is a very loose
      // upper bound that still catches a frozen/cached-forever response.
      final age = now.difference(tle.epoch.toUtc()).abs();
      expect(
        age,
        lessThan(const Duration(days: 30)),
        reason: 'TLE epoch ${tle.epoch} is stale relative to $now '
            '(age $age) - did we really fetch live data?',
      );
      // The facade epoch must agree with the source TLE epoch.
      expect(
        sat.epoch.toUtc().difference(tle.epoch.toUtc()).abs(),
        lessThan(const Duration(seconds: 1)),
      );
    });

    test('propagate(now) yields a finite, sane LEO ECI state', () {
      final state = sat.propagate(now);

      for (final c in <double>[
        state.position.x,
        state.position.y,
        state.position.z,
        state.velocity.x,
        state.velocity.y,
        state.velocity.z,
      ]) {
        expect(c.isFinite, isTrue, reason: 'ECI component must be finite');
      }

      // Geocentric radius: ISS orbits at ~420 km altitude, so |position| is
      // roughly Earth radius (~6378 km) + altitude. Allow a generous LEO band.
      final radiusKm = state.position.magnitude;
      expect(
        radiusKm,
        inInclusiveRange(6600, 7100),
        reason: 'geocentric radius $radiusKm km outside sane ISS LEO band',
      );

      // Orbital speed for a circular LEO at this radius is ~7.66 km/s.
      final speedKmS = state.velocity.magnitude;
      expect(
        speedKmS,
        inInclusiveRange(7.0, 8.0),
        reason: 'orbital speed $speedKmS km/s outside sane LEO band',
      );

      // ignore: avoid_print
      print('LIVE propagate: radius=${radiusKm.toStringAsFixed(1)} km '
          'speed=${speedKmS.toStringAsFixed(3)} km/s');
    });

    test('lookAngleAt(now) yields a well-formed look angle', () {
      final la = sat.lookAngleAt(now);

      expect(la.azimuthDeg, inInclusiveRange(0, 360));
      expect(la.azimuthDeg, lessThan(360));
      expect(la.elevationDeg, inInclusiveRange(-90, 90));
      expect(la.rangeKm, greaterThan(0));
      // `lookAngleAt` returns the true geometric slant distance regardless of
      // whether the satellite is above the horizon. When the ISS is on the far
      // side of the Earth (negative elevation) that distance approaches the
      // observer-to-far-side maximum of ~2 * (R_earth + alt) ~ 13600 km. Bound
      // it well above that so an above-horizon pass (range < ~2500 km) and a
      // below-horizon snapshot both pass, but a nonsense value still fails.
      expect(
        la.rangeKm,
        lessThan(14000),
        reason: 'slant range ${la.rangeKm} km exceeds the geometric maximum '
            'for a LEO object',
      );
      expect(la.rangeRateKmS.isFinite, isTrue);

      // ignore: avoid_print
      print('LIVE lookAngle: az=${la.azimuthDeg.toStringAsFixed(1)} '
          'el=${la.elevationDeg.toStringAsFixed(1)} '
          'range=${la.rangeKm.toStringAsFixed(1)} km');
    });

    test('subPointAt(now) yields a sane geodetic sub-point', () {
      final sp = sat.subPointAt(now);

      expect(sp.latitudeDeg, inInclusiveRange(-90, 90));
      // ISS inclination is ~51.6 deg, so the ground track stays within
      // roughly +/-53 deg latitude.
      expect(
        sp.latitudeDeg,
        inInclusiveRange(-53, 53),
        reason: 'sub-point latitude ${sp.latitudeDeg} outside ISS ground '
            'track band',
      );
      expect(sp.longitudeDeg, inInclusiveRange(-180, 180));
      expect(
        sp.altitudeKm,
        inInclusiveRange(300, 500),
        reason: 'sub-point altitude ${sp.altitudeKm} km outside ISS band',
      );

      // ignore: avoid_print
      print('LIVE subPoint: lat=${sp.latitudeDeg.toStringAsFixed(2)} '
          'lon=${sp.longitudeDeg.toStringAsFixed(2)} '
          'alt=${sp.altitudeKm.toStringAsFixed(1)} km');
    });

    test('passes over the next 3 days: at least one, each well-ordered', () {
      final to = now.add(const Duration(days: 3));
      final found = sat.passes(from: now, to: to);

      // A mid-latitude site sees the ISS several times a day, so 3 days must
      // contain at least one pass at or above 10 deg.
      expect(
        found,
        isNotEmpty,
        reason: 'expected at least one ISS pass over Warsaw within 3 days',
      );

      for (final pass in found) {
        expect(
          pass.rise.utc.isBefore(pass.culmination.utc),
          isTrue,
          reason: 'rise must precede culmination',
        );
        expect(
          pass.culmination.utc.isBefore(pass.set.utc),
          isTrue,
          reason: 'culmination must precede set',
        );
        expect(
          pass.peakElevationDeg,
          greaterThanOrEqualTo(10),
          reason: 'peak elevation must clear the 10 deg mask',
        );
        // Pass must lie inside the requested window.
        expect(pass.rise.utc.isBefore(now), isFalse);
        expect(pass.set.utc.isAfter(to), isFalse);
      }

      // ignore: avoid_print
      print('LIVE passes (3d, >=10 deg): count=${found.length} '
          'firstRise=${found.first.rise.utc} '
          'firstPeakEl=${found.first.peakElevationDeg.toStringAsFixed(1)}');
    });

    test('visiblePasses + nextVisiblePass run and return well-formed results',
        () {
      final to = now.add(const Duration(days: 3));

      // A visible pass may or may not exist depending on time-of-day/season,
      // so we do NOT require one - only that the calls run without throwing
      // and any result they produce is internally consistent.
      final visible = sat.visiblePasses(from: now, to: to);

      for (final pv in visible) {
        // isVisible must agree with whether intervals exist.
        expect(pv.isVisible, equals(pv.visibleIntervals.isNotEmpty));
        if (pv.isVisible) {
          expect(pv.visibleIntervals, isNotEmpty);
          for (final iv in pv.visibleIntervals) {
            // A visible interval must be non-empty and ordered.
            expect(iv.endUtc.isAfter(iv.startUtc), isTrue);
            // ... and contained within its parent pass window.
            expect(
              iv.startUtc.isBefore(pv.pass.rise.utc),
              isFalse,
              reason: 'visible interval starts before the pass rise',
            );
            expect(
              iv.endUtc.isAfter(pv.pass.set.utc),
              isFalse,
              reason: 'visible interval ends after the pass set',
            );
          }
        }
      }

      // nextVisiblePass must also just run; it returns null when no visible
      // pass exists in the window, which is acceptable.
      final next = sat.nextVisiblePass(
        after: now,
        within: const Duration(days: 3),
      );
      if (next != null) {
        expect(next.isVisible, isTrue);
        expect(next.visibleIntervals, isNotEmpty);
      }

      // ignore: avoid_print
      print('LIVE visiblePasses (3d): total=${visible.length} '
          'visible=${visible.where((p) => p.isVisible).length} '
          'nextVisible=${next == null ? 'none' : next.pass.rise.utc}');
    });

    test('isObserverInDarkness + isSatelliteSunlit return a bool', () {
      // Just prove the solar/eclipse paths execute on live elements without
      // throwing; the actual truth value depends on the current instant.
      final dark = sat.isObserverInDarkness(now);
      final sunlit = sat.isSatelliteSunlit(now);

      expect(dark, isA<bool>());
      expect(sunlit, isA<bool>());

      // ignore: avoid_print
      print('LIVE solar: observerInDarkness=$dark satelliteSunlit=$sunlit');
    });
  });
}
