import 'package:meta/meta.dart';

/// A ground station, given as a WGS-84 geodetic position.
///
/// Latitude and longitude are in degrees; altitude is in metres above the
/// WGS-84 reference ellipsoid (not above mean sea level). This is the
/// observer for topocentric look-angles and pass prediction.
///
/// * [latitudeDeg] is positive north, in `[-90, 90]`.
/// * [longitudeDeg] is positive east, in `[-180, 180]`.
/// * [altitudeMeters] is the height above the ellipsoid, in metres.
///
/// Out-of-range latitude or longitude throws an [ArgumentError] from the
/// constructor (a programming error in the supplied coordinates, distinct from
/// the runtime `GeometryException` raised by the geometry layer).
@immutable
final class Observer {
  /// Creates an observer at the given geodetic coordinates.
  ///
  /// Throws an [ArgumentError] if [latitudeDeg] is outside `[-90, 90]` or
  /// [longitudeDeg] is outside `[-180, 180]`.
  Observer({
    required this.latitudeDeg,
    required this.longitudeDeg,
    this.altitudeMeters = 0,
  }) {
    if (!(latitudeDeg >= -90.0 && latitudeDeg <= 90.0)) {
      throw ArgumentError.value(
        latitudeDeg,
        'latitudeDeg',
        'latitude must be in [-90, 90]',
      );
    }
    if (!(longitudeDeg >= -180.0 && longitudeDeg <= 180.0)) {
      throw ArgumentError.value(
        longitudeDeg,
        'longitudeDeg',
        'longitude must be in [-180, 180]',
      );
    }
  }

  /// Geodetic latitude in degrees, positive north, in `[-90, 90]`.
  final double latitudeDeg;

  /// Geodetic longitude in degrees, positive east, in `[-180, 180]` (closed).
  ///
  /// Note this accepts the closed range `[-180, 180]`, whereas a derived
  /// `SubSatellitePoint.longitudeDeg` is normalized to the half-open range
  /// `[-180, 180)` (the anti-meridian maps to `-180`). Consequently an observer
  /// constructed with `+180` does not round-trip through that normalization: it
  /// would come back as `-180`.
  final double longitudeDeg;

  /// Height above the WGS-84 ellipsoid, in metres.
  final double altitudeMeters;

  @override
  bool operator ==(Object other) =>
      other is Observer &&
      latitudeDeg == other.latitudeDeg &&
      longitudeDeg == other.longitudeDeg &&
      altitudeMeters == other.altitudeMeters;

  @override
  int get hashCode => Object.hash(latitudeDeg, longitudeDeg, altitudeMeters);

  @override
  String toString() => 'Observer(latitudeDeg: $latitudeDeg, '
      'longitudeDeg: $longitudeDeg, altitudeMeters: $altitudeMeters)';
}
