/// Base type for all exceptions thrown by the satellite_observer library.
///
/// This is a sealed hierarchy: every failure raised by the public API is one
/// of the listed subtypes, so callers can switch over them exhaustively.
sealed class SatelliteObserverException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  const SatelliteObserverException(this.message);

  /// A human-readable description of what went wrong.
  final String message;
}

/// Thrown when orbital elements are malformed or physically invalid.
///
/// Examples include a TLE with non-numeric fields, an eccentricity outside
/// `[0, 1)`, or a mean motion that is not positive.
final class InvalidElementsException extends SatelliteObserverException {
  /// Creates an [InvalidElementsException] with the given [message].
  const InvalidElementsException(super.message);

  @override
  String toString() => 'InvalidElementsException: $message';
}

/// Thrown when the SGP4/SDP4 propagation step fails.
///
/// Carries the Vallado SGP4 error [code] alongside a [message]. The defined
/// Vallado codes are:
///
/// * 1 - mean eccentricity out of range, or semi-major axis below 0.95 earth
///   radii.
/// * 2 - mean motion less than zero.
/// * 3 - perturbed eccentricity out of range.
/// * 4 - semi-latus rectum less than zero.
/// * 6 - satellite has decayed (radius below the earth's surface).
///
/// A code of 0 is never raised; it represents a successful propagation.
///
/// In addition to the Vallado codes (1..6), this library raises one
/// non-Vallado sentinel code, [nonFiniteOutputCode] (99), when the propagator
/// returns a non-finite position or velocity even though SGP4 itself reported
/// success. This guards against NaN/Inf leaking into a caller's state.
final class PropagationException extends SatelliteObserverException {
  /// Creates a [PropagationException] for the given SGP4 [code] and [message].
  const PropagationException(this.code, super.message);

  /// Sentinel [code] for a non-finite SGP4 output (NaN/Inf position or
  /// velocity) that is distinct from the Vallado codes (1..6).
  static const int nonFiniteOutputCode = 99;

  /// The SGP4 error code: a Vallado code (1, 2, 3, 4 or 6) or the non-Vallado
  /// [nonFiniteOutputCode] (99).
  final int code;

  @override
  String toString() => 'PropagationException(code: $code): $message';
}

/// Thrown when a geometric (look-angle / visibility) computation fails.
///
/// Reserved for the topocentric geometry layer; included here so the public
/// barrel can export the full exception hierarchy from the start.
final class GeometryException extends SatelliteObserverException {
  /// Creates a [GeometryException] with the given [message].
  const GeometryException(super.message);

  @override
  String toString() => 'GeometryException: $message';
}
