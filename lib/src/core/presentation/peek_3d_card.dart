import 'package:flutter/material.dart';

/// A premium 3D perspective tilt card that responds to mouse hover and cursor movement.
class Peek3DCard extends StatefulWidget {
  const Peek3DCard({
    super.key,
    required this.child,
    this.maxTiltAngle = 0.06,
    this.hoverScale = 1.02,
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
  double _rotateX = 0;
  double _rotateY = 0;
  bool _hovering = false;

  void _onHover(PointerEvent event, Size size) {
    if (size.width == 0 || size.height == 0) return;
    final dx = (event.localPosition.dx / size.width - 0.5) * 2;
    final dy = (event.localPosition.dy / size.height - 0.5) * 2;
    setState(() {
      _rotateX = -dy * widget.maxTiltAngle;
      _rotateY = dx * widget.maxTiltAngle;
    });
  }

  void _onEnter() {
    setState(() => _hovering = true);
  }

  void _onExit() {
    setState(() {
      _hovering = false;
      _rotateX = 0;
      _rotateY = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final s = _hovering ? widget.hoverScale : 1.0;
        return MouseRegion(
          onEnter: (_) => _onEnter(),
          onExit: (_) => _onExit(),
          onHover: (event) => _onHover(event, size),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..scaleByDouble(s, s, 1.0, 1.0)
                ..rotateX(_rotateX)
                ..rotateY(_rotateY),
              alignment: FractionalOffset.center,
              child: AnimatedPhysicalModel(
                duration: const Duration(milliseconds: 200),
                shape: BoxShape.rectangle,
                elevation: _hovering ? 12 : 0,
                color: Colors.transparent,
                shadowColor: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}
