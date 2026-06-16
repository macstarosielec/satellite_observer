import 'package:meta/meta.dart';

/// The topocentric look-angle from an observer to a satellite at an instant.
///
/// All angles are in degrees at this public boundary (ADR-13). The conventions
/// are:
///
/// * [azimuthDeg] - compass azimuth, `0` = north, increasing clockwise
///   (`90` = east), in `[0, 360)`.
/// * [elevationDeg] - angle above the local horizon; negative means the
///   satellite is below the horizon (geometric, no atmospheric refraction).
/// * [rangeKm] - straight-line slant range from the observer to the
///   satellite, in kilometres (FR-6).
/// * [rangeRateKmS] - line-of-sight range rate in kilometres per second,
///   positive when the satellite is receding from the observer (FR-7).
/// * [utc] - the UTC instant the look-angle is computed for.
@immutable
final class LookAngle {
  /// Creates a [LookAngle] with the given components at [utc].
  const LookAngle({
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.rangeKm,
    required this.rangeRateKmS,
    required this.utc,
  });

  /// Azimuth in degrees, `0` = north, clockwise, in `[0, 360)`.
  final double azimuthDeg;

  /// Elevation above the horizon in degrees; negative means below the horizon.
  final double elevationDeg;

  /// Slant range from the observer to the satellite, in kilometres.
  final double rangeKm;

  /// Line-of-sight range rate in kilometres per second, positive = receding.
  final double rangeRateKmS;

  /// The UTC instant this look-angle describes.
  ///
  /// Expected to be UTC (ADR-13); the value is carried through from the source
  /// `EciState.utc` unchanged.
  final DateTime utc;

  @override
  bool operator ==(Object other) =>
      other is LookAngle &&
      azimuthDeg == other.azimuthDeg &&
      elevationDeg == other.elevationDeg &&
      rangeKm == other.rangeKm &&
      rangeRateKmS == other.rangeRateKmS &&
      utc.isAtSameMomentAs(other.utc);

  @override
  int get hashCode => Object.hash(
        azimuthDeg,
        elevationDeg,
        rangeKm,
        rangeRateKmS,
        utc.microsecondsSinceEpoch,
      );

  @override
  String toString() => 'LookAngle(azimuthDeg: $azimuthDeg, '
      'elevationDeg: $elevationDeg, rangeKm: $rangeKm, '
      'rangeRateKmS: $rangeRateKmS, utc: $utc)';
}
