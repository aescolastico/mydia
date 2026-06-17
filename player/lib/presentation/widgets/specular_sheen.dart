import 'package:flutter/material.dart';

import '../../core/ui/reduced_motion.dart';

/// Wraps [child] with a subtle cursor-tracking specular highlight for desktop
/// depth (plan U6 / R9).
///
/// The cursor position is pushed into a [ValueNotifier] on hover and only a
/// thin [RadialGradient] overlay rebuilds via [ValueListenableBuilder] — the
/// wrapped [child] never rebuilds, and we never `setState` per hover tick. The
/// sheen layer is isolated in a [RepaintBoundary].
///
/// When the user prefers reduced motion the sheen is removed entirely: no
/// listener is attached and only the flat [child] is rendered (plan AE4).
///
/// A [BoxDecoration] radial gradient is used (not a `ShaderMask`) to avoid
/// `saveLayer` cost across many simultaneously-hoverable cards.
class SpecularSheen extends StatefulWidget {
  /// The content the sheen overlays.
  final Widget child;

  /// Corner radius of the sheen clip, matched to the host (e.g. a card).
  final BorderRadius borderRadius;

  /// Peak opacity of the sheen highlight at the cursor.
  final double intensity;

  /// Radius of the radial sheen as a fraction of the shorter side.
  final double radiusFactor;

  const SpecularSheen({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.intensity = 0.12,
    this.radiusFactor = 0.6,
  });

  /// Maps a local cursor [position] inside a box of [size] to the [Alignment]
  /// used as the radial-gradient center (-1..1 on each axis). Exposed for
  /// testing the position math independently of pointer simulation.
  static Alignment alignmentFor(Offset position, Size size) {
    if (size.width <= 0 || size.height <= 0) return Alignment.center;
    final dx = (position.dx / size.width) * 2 - 1;
    final dy = (position.dy / size.height) * 2 - 1;
    return Alignment(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
  }

  @override
  State<SpecularSheen> createState() => _SpecularSheenState();
}

class _SpecularSheenState extends State<SpecularSheen> {
  /// Cursor position within the widget, in local logical pixels. Null when the
  /// pointer is outside (sheen hidden).
  final ValueNotifier<Offset?> _cursor = ValueNotifier<Offset?>(null);

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion: render the flat child only, no listener, no sheen.
    if (context.reduceMotion) {
      return widget.child;
    }

    return MouseRegion(
      onHover: (event) => _cursor.value = event.localPosition,
      onExit: (_) => _cursor.value = null,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: RepaintBoundary(
              child: IgnorePointer(
                child: ValueListenableBuilder<Offset?>(
                  valueListenable: _cursor,
                  builder: (context, cursor, _) {
                    if (cursor == null) return const SizedBox.shrink();
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.biggest;
                        return ClipRRect(
                          borderRadius: widget.borderRadius,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: SpecularSheen.alignmentFor(cursor, size),
                                radius: widget.radiusFactor,
                                colors: [
                                  Colors.white
                                      .withValues(alpha: widget.intensity),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 1.0],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
