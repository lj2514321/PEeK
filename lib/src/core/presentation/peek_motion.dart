import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/material.dart';

/// Keeps every visited destination mounted while animating only opacity and a
/// small composited translation between the active pages.
///
/// This avoids media-library reloads and layout animation jank while still
/// giving top-level navigation a clear sense of direction.
class PeekIndexedTransitionStack extends StatelessWidget {
  const PeekIndexedTransitionStack({
    super.key,
    required this.index,
    required this.children,
  }) : assert(children.length > 0),
       assert(index >= 0 && index < children.length);

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final enterDuration = AppMotion.responsive(context, AppMotion.slow);
    final exitDuration = AppMotion.responsive(context, AppMotion.standard);

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var childIndex = 0; childIndex < children.length; childIndex++)
            _DestinationMotionLayer(
              key: ValueKey('peek-destination-$childIndex'),
              active: childIndex == index,
              offset: _offsetFor(childIndex),
              enterDuration: enterDuration,
              exitDuration: exitDuration,
              child: children[childIndex],
            ),
        ],
      ),
    );
  }

  Offset _offsetFor(int childIndex) {
    if (childIndex == index) return Offset.zero;
    return Offset(childIndex < index ? -0.024 : 0.024, 0);
  }
}

class _DestinationMotionLayer extends StatefulWidget {
  const _DestinationMotionLayer({
    super.key,
    required this.active,
    required this.offset,
    required this.enterDuration,
    required this.exitDuration,
    required this.child,
  });

  final bool active;
  final Offset offset;
  final Duration enterDuration;
  final Duration exitDuration;
  final Widget child;

  @override
  State<_DestinationMotionLayer> createState() =>
      _DestinationMotionLayerState();
}

class _DestinationMotionLayerState extends State<_DestinationMotionLayer> {
  late bool _offstage;

  @override
  void initState() {
    super.initState();
    _offstage = !widget.active;
  }

  @override
  void didUpdateWidget(_DestinationMotionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _offstage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.active ? widget.enterDuration : widget.exitDuration;
    final curve = widget.active ? AppMotion.enterCurve : AppMotion.exitCurve;

    return Offstage(
      offstage: _offstage,
      child: AnimatedSlide(
        offset: widget.offset,
        duration: duration,
        curve: curve,
        child: AnimatedScale(
          scale: widget.active ? 1.0 : 0.94,
          duration: duration,
          curve: curve,
          child: AnimatedOpacity(
            opacity: widget.active ? 1.0 : 0.0,
            duration: duration,
            curve: curve,
            onEnd: () {
              if (!widget.active && !_offstage && mounted) {
                setState(() => _offstage = true);
              }
            },
            child: Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0008)
                ..rotateY(widget.active ? 0.0 : (widget.offset.dx < 0 ? 0.018 : -0.018)),
              alignment: FractionalOffset.center,
              child: IgnorePointer(
                ignoring: !widget.active,
                child: ExcludeFocus(
                  excluding: !widget.active,
                  child: ExcludeSemantics(
                    excluding: !widget.active,
                    child: TickerMode(
                      enabled: widget.active,
                      child: RepaintBoundary(child: widget.child),
                    ),
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
