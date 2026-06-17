import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

/// A single reusable frosted-glass surface that subsumes the player's three
/// ad-hoc `BackdropFilter` variants (app bar, modal, card hover overlay).
///
/// Internally this is `RepaintBoundary > ClipRRect > BackdropFilter > fill`,
/// so live blur stays isolated to small fixed-position chrome (R8/R11) and the
/// blur region repaints independently of surrounding content.
///
/// Use the named constructors ([GlassSurface.appBar], [GlassSurface.modal],
/// [GlassSurface.hoverOverlay]) to reproduce the existing visual treatments
/// exactly; the unnamed constructor is available for bespoke surfaces.
///
/// When several glass surfaces are visible at once, wrap them in a
/// [BackdropGroup] and pass `grouped: true` so they share a single backdrop
/// rendering pass (uses [BackdropFilter.grouped]).
class GlassSurface extends StatelessWidget {
  /// Gaussian blur sigma applied behind the surface.
  final double blurSigma;

  /// Solid fill painted over the blur. Ignored when [gradient] is set.
  final Color? fillColor;

  /// Optional gradient fill painted over the blur (e.g. the card hover scrim).
  /// Takes precedence over [fillColor] when both are provided.
  final Gradient? gradient;

  /// Corner radius for the clip and border.
  final BorderRadius borderRadius;

  /// Optional border drawn on the fill.
  final BoxBorder? border;

  /// Whether to participate in an enclosing [BackdropGroup] for a shared
  /// rendering pass. Requires a [BackdropGroup] ancestor.
  final bool grouped;

  final Widget? child;

  const GlassSurface({
    super.key,
    required this.blurSigma,
    this.fillColor,
    this.gradient,
    this.borderRadius = BorderRadius.zero,
    this.border,
    this.grouped = false,
    this.child,
  });

  /// App-bar chrome glass: blur sigma 10, [AppColors.background] fill, no
  /// border, square corners. Pass [opacity] to override the fill alpha
  /// (0.85 for the library/downloads bars, 0.8 elsewhere).
  GlassSurface.appBar({
    Key? key,
    double opacity = 0.8,
    bool grouped = false,
    Widget? child,
  }) : this(
          key: key,
          blurSigma: 10,
          fillColor: AppColors.background.withValues(alpha: opacity),
          grouped: grouped,
          child: child,
        );

  /// Modal / sheet glass: blur sigma 8, [AppColors.surface] @0.6 fill,
  /// [AppColors.border] @0.2 border, radius 20.
  GlassSurface.modal({
    Key? key,
    bool grouped = false,
    Widget? child,
  }) : this(
          key: key,
          blurSigma: 8,
          fillColor: AppColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.2),
          ),
          grouped: grouped,
          child: child,
        );

  /// Media-card hover overlay glass: blur sigma 2, vertical black gradient
  /// (0.3 -> 0.6), radius 12.
  GlassSurface.hoverOverlay({
    Key? key,
    BorderRadius? borderRadius,
    bool grouped = false,
    Widget? child,
  }) : this(
          key: key,
          blurSigma: 2,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.3),
              Colors.black.withValues(alpha: 0.6),
            ],
          ),
          borderRadius: borderRadius ?? BorderRadius.circular(12),
          grouped: grouped,
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    final filter = ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma);
    final backdrop = grouped
        ? BackdropFilter.grouped(filter: filter, child: _fill())
        : BackdropFilter(filter: filter, child: _fill());

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: backdrop,
      ),
    );
  }

  Widget _fill() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? fillColor : null,
        gradient: gradient,
        borderRadius: borderRadius,
        border: border,
      ),
      child: child,
    );
  }
}
