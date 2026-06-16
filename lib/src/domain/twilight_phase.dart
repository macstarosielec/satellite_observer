/// A self-documenting darkness gate for observer twilight (ADR-7, FR-12).
///
/// Each phase names a conventional Sun-below-horizon threshold. An observer is
/// "in darkness" for a given phase when the Sun's topocentric altitude is below
/// that phase's [sunAltitudeDegrees]. The default throughout the API is
/// [civil] (`-6` deg), the conventional naked-eye bright-satellite gate (it
/// matches Heavens-Above / sat-spotter).
///
/// For full control, the visibility/darkness APIs also accept a raw
/// `sunAltitudeBelowDeg` angle that overrides the enum; the enum is the
/// recommended path. Adding enum values later is a MINOR change but breaks an
/// exhaustive `switch`, so consumers that switch on this enum should include a
/// `default` clause.
enum TwilightPhase {
  /// Sun `6` deg below the horizon: the naked-eye bright-satellite gate and the
  /// API default. Brighter passes (e.g. the ISS) are visible from civil
  /// twilight onward.
  civil(-6),

  /// Sun `12` deg below the horizon: a darker sky for fainter objects.
  nautical(-12),

  /// Sun `18` deg below the horizon: full astronomical darkness, the faintest
  /// gate.
  astronomical(-18);

  /// Associates each phase with its Sun-altitude threshold, in degrees.
  const TwilightPhase(this.sunAltitudeDegrees);

  /// The Sun's topocentric altitude threshold for this phase, in degrees.
  ///
  /// The observer is in darkness for this phase when the Sun's altitude is
  /// strictly below this (negative) value.
  final double sunAltitudeDegrees;
}
