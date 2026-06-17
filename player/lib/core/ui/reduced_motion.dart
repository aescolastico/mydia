import 'package:flutter/widgets.dart';

/// Helpers for honoring the user's reduced-motion / accessibility preferences
/// when deciding whether to play decorative animations.
///
/// On Flutter web (SDK >= 3.38) `MediaQuery.disableAnimationsOf` is backed by
/// the browser's `prefers-reduced-motion` media query, so reading it reactively
/// in `build` lets widgets respond to OS/browser changes at runtime.
///
/// Consumers should read [ReducedMotion.of] in their `build` method (so the
/// dependency is registered and the widget rebuilds when the preference flips)
/// and then choose `Duration.zero` / a final-state render when motion is
/// suppressed. See [ReducedMotionContext] for the extension form.
abstract final class ReducedMotion {
  /// Whether decorative motion should be suppressed for the current context.
  ///
  /// Returns `true` when the platform requests disabled animations or when
  /// accessible navigation (e.g. a screen reader / switch access) is active.
  /// Reads `MediaQuery` reactively, so callers rebuild when the value changes.
  static bool of(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
  }

  /// Returns [duration] when motion is allowed, otherwise [Duration.zero].
  ///
  /// Convenience for gating animation/crossfade durations.
  static Duration duration(BuildContext context, Duration duration) {
    return of(context) ? Duration.zero : duration;
  }
}

/// Context extension mirroring [ReducedMotion] for ergonomic call sites.
extension ReducedMotionContext on BuildContext {
  /// Whether decorative motion should be suppressed. See [ReducedMotion.of].
  bool get reduceMotion => ReducedMotion.of(this);

  /// See [ReducedMotion.duration].
  Duration reducedMotionDuration(Duration duration) =>
      ReducedMotion.duration(this, duration);
}
