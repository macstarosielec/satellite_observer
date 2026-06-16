import 'dart:math' as math;

import 'package:meta/meta.dart';

/// An immutable Cartesian 3-vector.
///
/// Used throughout the library as both a position (kilometres) and a velocity
/// (kilometres per second), depending on context. The interpretation of the
/// components is documented by the API that returns or consumes the vector;
/// the type itself is unit-agnostic.
@immutable
final class Vector3 {
  /// Creates a vector with the given [x], [y] and [z] components.
  const Vector3(this.x, this.y, this.z);

  /// The x component.
  final double x;

  /// The y component.
  final double y;

  /// The z component.
  final double z;

  /// The Euclidean magnitude (length) of this vector.
  double get magnitude => math.sqrt(x * x + y * y + z * z);

  // Equality and hashCode follow IEEE-754 double semantics: a vector with a
  // NaN component is not equal to itself (NaN != NaN), and -0.0 hashes equal
  // to 0.0. Callers comparing potentially-NaN vectors must account for this.
  @override
  bool operator ==(Object other) =>
      other is Vector3 && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vector3($x, $y, $z)';
}
