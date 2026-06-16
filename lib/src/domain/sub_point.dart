import 'package:meta/meta.dart';

/// The sub-satellite point: the geodetic position directly beneath a satellite.
///
/// This is the WGS-84 geodetic point on the Earth where the line from the
/// Earth's centre through the satellite meets the surface, plus the
/// satellite's geodetic height (FR-8).
///
/// * [latitudeDeg] - geodetic latitude in degrees, positive north.
/// * [longitudeDeg] - geodetic longitude in degrees, positive east, in
///   `[-180, 180)`.
/// * [altitudeKm] - height above the WGS-84 ellipsoid, in kilometres.
@immutable
final class SubSatellitePoint {
  /// Creates a [SubSatellitePoint] with the given geodetic coordinates.
  const SubSatellitePoint({
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.altitudeKm,
  });

  /// Geodetic latitude in degrees, positive north.
  final double latitudeDeg;

  /// Geodetic longitude in degrees, positive east, in `[-180, 180)`.
  final double longitudeDeg;

  /// Height above the WGS-84 ellipsoid, in kilometres.
  final double altitudeKm;

  @override
  bool operator ==(Object other) =>
      other is SubSatellitePoint &&
      latitudeDeg == other.latitudeDeg &&
      longitudeDeg == other.longitudeDeg &&
      altitudeKm == other.altitudeKm;

  @override
  int get hashCode => Object.hash(latitudeDeg, longitudeDeg, altitudeKm);

  @override
  String toString() => 'SubSatellitePoint(latitudeDeg: $latitudeDeg, '
      'longitudeDeg: $longitudeDeg, altitudeKm: $altitudeKm)';
}
