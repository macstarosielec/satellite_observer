import 'package:meta/meta.dart';
import 'package:satellite_observer/src/domain/look_angle.dart';
import 'package:satellite_observer/src/domain/pass.dart';

/// A contiguous sub-arc of a [Pass] during which the satellite is actually
/// visible to the naked eye: the observer is in darkness AND the satellite is
/// sunlit (FR-14).
///
/// The interval `[startUtc, endUtc]` is the portion of the pass that satisfies
/// both conditions; a single pass can contain more than one such interval (for
/// example if the satellite briefly enters Earth's shadow mid-pass). All times
/// are UTC (ADR-13).
@immutable
final class VisibleInterval {
  /// Creates a [VisibleInterval] spanning `[startUtc, endUtc]` with the
  /// brightest-geometry [peakLookAngle] inside it.
  const VisibleInterval({
    required this.startUtc,
    required this.endUtc,
    required this.peakLookAngle,
  });

  /// The UTC start of the visible sub-arc (the satellite becomes both sunlit
  /// and seen against a dark-enough sky).
  final DateTime startUtc;

  /// The UTC end of the visible sub-arc.
  final DateTime endUtc;

  /// The look-angle at the highest-elevation instant within this interval.
  ///
  /// This is the moment the satellite is best placed (highest above the
  /// horizon) while visible; useful as the "look here" pointer for the
  /// interval.
  final LookAngle peakLookAngle;

  @override
  bool operator ==(Object other) =>
      other is VisibleInterval &&
      startUtc.isAtSameMomentAs(other.startUtc) &&
      endUtc.isAtSameMomentAs(other.endUtc) &&
      peakLookAngle == other.peakLookAngle;

  @override
  int get hashCode => Object.hash(
        startUtc.microsecondsSinceEpoch,
        endUtc.microsecondsSinceEpoch,
        peakLookAngle,
      );

  @override
  String toString() => 'VisibleInterval(startUtc: $startUtc, '
      'endUtc: $endUtc, peakLookAngle: $peakLookAngle)';
}

/// The naked-eye visibility verdict for a single [Pass] (FR-14) - the headline
/// result of the library.
///
/// A pass that is geometrically above the horizon is only *visible* where the
/// observer is in darkness AND the satellite is sunlit. [visibleIntervals]
/// holds those sub-arcs (empty if the pass is never visible); [isVisible] is a
/// convenience for `visibleIntervals.isNotEmpty`.
@immutable
final class PassVisibility {
  /// Creates a [PassVisibility] for [pass] with its [visibleIntervals].
  ///
  /// [isVisible] must equal `visibleIntervals.isNotEmpty`; the calculator
  /// constructs it consistently.
  const PassVisibility({
    required this.pass,
    required this.isVisible,
    required this.visibleIntervals,
  });

  /// The underlying geometric pass (rise/culmination/set).
  final Pass pass;

  /// Whether any [VisibleInterval] exists for this pass.
  final bool isVisible;

  /// The visible sub-arcs of the pass, in time order (empty when not visible).
  final List<VisibleInterval> visibleIntervals;

  @override
  bool operator ==(Object other) =>
      other is PassVisibility &&
      pass == other.pass &&
      isVisible == other.isVisible &&
      _listEquals(visibleIntervals, other.visibleIntervals);

  @override
  int get hashCode =>
      Object.hash(pass, isVisible, Object.hashAll(visibleIntervals));

  @override
  String toString() => 'PassVisibility(pass: $pass, isVisible: $isVisible, '
      'visibleIntervals: $visibleIntervals)';

  static bool _listEquals(List<VisibleInterval> a, List<VisibleInterval> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
