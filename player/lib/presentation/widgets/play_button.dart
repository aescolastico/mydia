import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

class PlayButton extends StatefulWidget {
  final VoidCallback? onPressed;

  const PlayButton({
    super.key,
    this.onPressed,
  });

  @override
  State<PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<PlayButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  bool get _enabled => widget.onPressed != null;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const double _size = 52.0;

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _enabled
                ? const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: _enabled ? null : AppColors.surfaceVariant,
            boxShadow: _enabled
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onPressed,
              onTapDown: _enabled ? (_) => _controller.forward() : null,
              onTapUp: _enabled ? (_) => _controller.reverse() : null,
              onTapCancel: _enabled ? () => _controller.reverse() : null,
              child: Center(
                child: Padding(
                  // Slight right offset to optically center the play triangle
                  padding: const EdgeInsets.only(left: 3),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 28,
                    color: _enabled ? Colors.white : AppColors.textDisabled,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
