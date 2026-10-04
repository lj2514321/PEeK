import 'dart:math' as math;
import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/material.dart';

/// A GPU-composited, rotating luminescence border beam that courses around
/// a rounded rectangle perimeter to give focused/active HUD capsules living energy.
class PeekBorderBeam extends StatefulWidget {
  const PeekBorderBeam({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.borderWidth = 1.4,
    this.beamColor = AppColors.spotlight,
    this.secondaryColor = AppColors.spotlightLight,
    this.duration = const Duration(seconds: 4),
    this.active = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double borderWidth;
  final Color beamColor;
  final Color secondaryColor;
  final Duration duration;
  final bool active;

  @override
  State<PeekBorderBeam> createState() => _PeekBorderBeamState();
}

class _PeekBorderBeamState extends State<PeekBorderBeam>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!AppMotion.isTest && widget.active) {
      _controller = AnimationController(
        vsync: this,
        duration: widget.duration,
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(PeekBorderBeam oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (AppMotion.isTest) return;
    if (widget.active && _controller == null) {
      _controller = AnimationController(
        vsync: this,
        duration: widget.duration,
      )..repeat();
    } else if (!widget.active && _controller != null) {
      _controller?.stop();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isTest || !widget.active || _controller == null) {
      return widget.child;
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller!,
        builder: (context, child) {
          final progress = _controller!.value;
          return CustomPaint(
            foregroundPainter: _BorderBeamPainter(
              progress: progress,
              borderRadius: widget.borderRadius,
              borderWidth: widget.borderWidth,
              beamColor: widget.beamColor,
              secondaryColor: widget.secondaryColor,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _BorderBeamPainter extends CustomPainter {
  _BorderBeamPainter({
    required this.progress,
    required this.borderRadius,
    required this.borderWidth,
    required this.beamColor,
    required this.secondaryColor,
  });

  final double progress;
  final BorderRadius borderRadius;
  final double borderWidth;
  final Color beamColor;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(borderWidth / 2);

    final angle = progress * 2 * math.pi;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..shader = SweepGradient(
        center: Alignment.center,
        transform: GradientRotation(angle),
        colors: [
          Colors.transparent,
          beamColor.withValues(alpha: 0.15),
          secondaryColor.withValues(alpha: 0.95),
          beamColor.withValues(alpha: 0.8),
          Colors.transparent,
        ],
        stops: const [0.0, 0.08, 0.18, 0.28, 0.40],
      ).createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_BorderBeamPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.beamColor != beamColor ||
        oldDelegate.borderWidth != borderWidth;
  }
}
