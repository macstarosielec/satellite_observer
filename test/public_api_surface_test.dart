/// Public API surface freeze (v1.0.0).
///
/// This file only COMPILES if every symbol intentionally exported from
/// `package:satellite_observer/satellite_observer.dart` resolves, so removing
/// or renaming a public symbol breaks the build here - a semver canary
/// guarding the frozen v1.0.0 contract. (Adding a new export is non-breaking
/// and is not caught here.) The `isNotNull` checks on Type literals are
/// compile-time resolution checks, not behaviour assertions; the enum-value
/// checks below are real semver-sensitive assertions.
///
/// Internal types (the `Sgp4Engine` internals, all `transforms/`, `passes/`,
/// `solar/`, and `visibility/` helpers, GMST, and the angle utilities) are
/// deliberately NOT exported and are unreferenceable through the barrel.
library;

import 'package:satellite_observer/satellite_observer.dart';
import 'package:test/test.dart';

void main() {
  test('all v1.0.0 public types are exported from the barrel', () {
    // L1 - propagation
    expect(GpElements, isNotNull);
    expect(EciState, isNotNull);
    expect(Vector3, isNotNull);
    expect(PropagationEngine, isNotNull);
    expect(Sgp4Engine, isNotNull);
    expect(GravityModel, isNotNull);
    // L2 - topocentric geometry
    expect(Observer, isNotNull);
    expect(LookAngle, isNotNull);
    expect(SubSatellitePoint, isNotNull);
    // L3 - passes
    expect(Pass, isNotNull);
    expect(PassEvent, isNotNull);
    expect(PassEventKind, isNotNull);
    expect(HorizonMask, isNotNull);
    // L4 - visibility
    expect(TwilightPhase, isNotNull);
    expect(VisibleInterval, isNotNull);
    expect(PassVisibility, isNotNull);
    // Facade + error tree
    expect(SatelliteObserver, isNotNull);
    expect(SatelliteObserverException, isNotNull);
    expect(InvalidElementsException, isNotNull);
    expect(PropagationException, isNotNull);
    expect(GeometryException, isNotNull);
  });

  test('frozen enum members (removing/renaming a value is a breaking change)',
      () {
    expect(TwilightPhase.values, hasLength(3));
    expect(TwilightPhase.civil.sunAltitudeDegrees, -6);
    expect(TwilightPhase.nautical.sunAltitudeDegrees, -12);
    expect(TwilightPhase.astronomical.sunAltitudeDegrees, -18);

    expect(
      GravityModel.values,
      containsAll(<GravityModel>[GravityModel.wgs72, GravityModel.wgs84]),
    );

    expect(
      PassEventKind.values,
      containsAll(<PassEventKind>[
        PassEventKind.rise,
        PassEventKind.culmination,
        PassEventKind.set,
      ]),
    );

    expect(
      HorizonMask.values,
      containsAll(<HorizonMask>[HorizonMask.openSky, HorizonMask.obstructed]),
    );
  });
}
