import 'package:flutter/material.dart';

/// A VisionOS-inspired 3D perspective card with dynamic specular glare reflection
/// and ambient glow shadow.
class Peek3DCard extends StatefulWidget {
  const Peek3DCard({
    super.key,
    required this.child,
    this.maxTiltAngle = 0.028,
    this.hoverScale = 1.025,
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
  double _dx = 0;
  double _dy = 0;
  bool _hovering = false;

  void _onHover(PointerEvent event, Size size) {
    if (size.width == 0 || size.height == 0) return;
    final normX = (event.localPosition.dx / size.width - 0.5) * 2;
    final normY = (event.localPosition.dy / size.height - 0.5) * 2;
    setState(() {
      _dx = normX.clamp(-1.0, 1.0);
      _dy = normY.clamp(-1.0, 1.0);
    });
  }

  void _onEnter() {
    setState(() => _hovering = true);
  }

  void _onExit() {
    setState(() {
      _hovering = false;
      _dx = 0;
      _dy = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rotateX = -_dy * widget.maxTiltAngle;
    final rotateY = _dx * widget.maxTiltAngle;
    final scale = _hovering ? widget.hoverScale : 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          onEnter: (_) => _onEnter(),
          onExit: (_) => _onExit(),
          onHover: (event) => _onHover(event, size),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutQuad,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0005)
                ..scaleByDouble(scale, scale, 1.0, 1.0)
                ..rotateX(rotateX)
                ..rotateY(rotateY),
              alignment: FractionalOffset.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: _hovering ? 0.24 : 0.0),
                  width: 1.2,
                ),
                boxShadow: _hovering
                    ? [
                        BoxShadow(
                          color: const Color(0x384A90E2),
                          blurRadius: 24,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : const [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    widget.child,
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: _hovering ? 1.0 : 0.0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(_dx * 0.7, _dy * 0.7),
                                radius: 0.85,
                                colors: [
                                  Colors.white.withValues(alpha: 0.18),
                                  Colors.white.withValues(alpha: 0.04),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.45, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
