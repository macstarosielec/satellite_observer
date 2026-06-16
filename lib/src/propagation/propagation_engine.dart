import 'package:satellite_observer/src/domain/eci_state.dart';

/// A propagator that turns orbital elements into a satellite state over time.
abstract interface class PropagationEngine {
  /// Propagates the orbit to the given [utc] instant.
  ///
  /// Returns the satellite [EciState] (TEME frame, km and km/s) whose `utc`
  /// field equals [utc].
  ///
  /// A non-UTC DateTime is normalised to UTC; pass UTC to avoid surprises.
  EciState propagate(DateTime utc);

  /// The epoch of the underlying elements, as a UTC instant.
  DateTime get epoch;
}
