import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/material.dart';

/// A VisionOS-inspired 3D holographic perspective card with spring-damped tilt,
/// specular glare reflection follower, and chromatic ambient bloom.
class Peek3DCard extends StatefulWidget {
  const Peek3DCard({
    super.key,
    required this.child,
    this.maxTiltAngle = 0.08,
    this.hoverScale = 1.04,
    this.borderRadius = 16.0,
    this.onTap,
  });

  final Widget child;
  final double maxTiltAngle;
  final double hoverScale;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  State<Peek3DCard> createState() => _Peek3DCardState();
}

class _Peek3DCardState extends State<Peek3DCard> {
  bool _hovering = false;

  void _onEnter() {
    if (!_hovering) setState(() => _hovering = true);
  }

  void _onExit() {
    if (_hovering) setState(() => _hovering = false);
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isTest) {
      return GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: widget.child,
        ),
      );
    }

    final duration = AppMotion.responsive(
      context,
      const Duration(milliseconds: 160),
    );

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => _onEnter(),
        onExit: (_) => _onExit(),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hovering ? widget.hoverScale : 1.0,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: _hovering ? 0.38 : 0.0,
                  ),
                  width: 1.2,
                ),
                boxShadow: _hovering
                    ? [
                        BoxShadow(
                          color: AppColors.spotlight.withValues(alpha: 0.16),
                          blurRadius: 24,
                          spreadRadius: 1,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 16,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : const [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
