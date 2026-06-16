import 'package:meta/meta.dart';
import 'package:satellite_observer/src/domain/geo/vector3.dart';

/// An instantaneous satellite state in the Earth-Centred Inertial frame.
///
/// SGP4/SDP4 produce coordinates in the True Equator Mean Equinox (TEME) frame
/// of date, which is the inertial frame used throughout this library.
///
/// * [position] is in kilometres.
/// * [velocity] is in kilometres per second.
/// * [utc] is the UTC instant the state corresponds to.
@immutable
final class EciState {
  /// Creates an [EciState] at [utc] with the given [position] and [velocity].
  const EciState({
    required this.position,
    required this.velocity,
    required this.utc,
  });

  /// Position vector in the TEME frame, in kilometres.
  final Vector3 position;

  /// Velocity vector in the TEME frame, in kilometres per second.
  final Vector3 velocity;

  /// The UTC instant this state describes.
  final DateTime utc;

  @override
  bool operator ==(Object other) =>
      other is EciState &&
      position == other.position &&
      velocity == other.velocity &&
      utc.isAtSameMomentAs(other.utc);

  @override
  int get hashCode =>
      Object.hash(position, velocity, utc.microsecondsSinceEpoch);

  @override
  String toString() =>
      'EciState(position: $position, velocity: $velocity, utc: $utc)';
}
