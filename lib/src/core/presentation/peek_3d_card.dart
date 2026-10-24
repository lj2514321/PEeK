import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A VisionOS-inspired 3D holographic perspective card with spring-damped micro-tilt,
/// pointer-tracked specular light sheen reflection, tactile press compression,
/// and origin-anchored route tracking.
class Peek3DCard extends StatefulWidget {
  const Peek3DCard({
    super.key,
    required this.child,
    this.maxTiltAngle = 0.045,
    this.hoverScale = 1.032,
    this.borderRadius = AppRadius.value,
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
  bool _pressed = false;
  final ValueNotifier<Offset> _pointerAlignment = ValueNotifier<Offset>(
    Offset.zero,
  );

  @override
  void dispose() {
    _pointerAlignment.dispose();
    super.dispose();
  }

  void _onEnter(PointerEnterEvent event) {
    if (!_hovering) setState(() => _hovering = true);
    _updatePointer(event.localPosition);
  }

  void _onHover(PointerHoverEvent event) {
    _updatePointer(event.localPosition);
  }

  void _onExit(PointerExitEvent event) {
    if (_hovering || _pressed) {
      setState(() {
        _hovering = false;
        _pressed = false;
      });
    }
    _pointerAlignment.value = Offset.zero;
  }

  void _onPointerDown(PointerDownEvent event) {
    PeekMotionOrigin.recordTap(context, event.position);
    if (!_pressed) setState(() => _pressed = true);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_pressed) setState(() => _pressed = false);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_pressed) setState(() => _pressed = false);
  }

  void _updatePointer(Offset localPosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final size = renderBox.size;
    if (size.width <= 0 || size.height <= 0) return;

    final dx = ((localPosition.dx / size.width) * 2.0 - 1.0).clamp(-1.0, 1.0);
    final dy = ((localPosition.dy / size.height) * 2.0 - 1.0).clamp(-1.0, 1.0);
    _pointerAlignment.value = Offset(dx, dy);
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
      _pressed
          ? const Duration(milliseconds: 110)
          : const Duration(milliseconds: 220),
    );
    final radius = BorderRadius.circular(widget.borderRadius);
    final targetScale = _pressed
        ? 0.965
        : (_hovering ? widget.hoverScale : 1.0);

    return RepaintBoundary(
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: MouseRegion(
          onEnter: _onEnter,
          onHover: _onHover,
          onExit: _onExit,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: targetScale,
              duration: duration,
              curve: PeekCurves.spatialEnter,
              child: ValueListenableBuilder<Offset>(
                valueListenable: _pointerAlignment,
                builder: (context, pointer, child) {
                  final tiltX = _hovering
                      ? -pointer.dy * widget.maxTiltAngle
                      : 0.0;
                  final tiltY = _hovering
                      ? pointer.dx * widget.maxTiltAngle
                      : 0.0;
                  final matrix = (tiltX == 0.0 && tiltY == 0.0)
                      ? Matrix4.identity()
                      : (Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateX(tiltX)
                          ..rotateY(tiltY));

                  return Transform(
                    alignment: Alignment.center,
                    transform: matrix,
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        child!,
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _hovering ? 1.0 : 0.0,
                              duration: duration,
                              curve: PeekCurves.spatialEnter,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: radius,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.42),
                                    width: 1.25,
                                  ),
                                  gradient: RadialGradient(
                                    center: Alignment(
                                      pointer.dx * 0.85,
                                      pointer.dy * 0.85,
                                    ),
                                    radius: 1.15,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.16),
                                      Colors.white.withValues(alpha: 0.03),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.48, 1.0],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: RepaintBoundary(child: ClipRRect(borderRadius: radius, child: widget.child)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
