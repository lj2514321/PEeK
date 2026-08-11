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
              if (!widget.active && mounted) {
                setState(() => _offstage = true);
              }
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A GPU-accelerated Matrix4 3D spatial depth page route that replaces native 2D page transitions.
class Peek3DPageRoute<T> extends PageRouteBuilder<T> {
  Peek3DPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.transitionDuration = const Duration(milliseconds: 380),
    super.reverseTransitionDuration = const Duration(milliseconds: 300),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: const Cubic(0.12, 0.88, 0.22, 1.0),
              reverseCurve: Curves.easeInQuad,
            );

            return AnimatedBuilder(
              animation: curvedAnimation,
              builder: (context, child) {
                final value = curvedAnimation.value;
                final scale = 0.93 + (value * 0.07);
                final rotateY = (1.0 - value) * 0.08;
                final opacity = value.clamp(0.0, 1.0);

                return Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0008)
                    ..scaleByDouble(scale, scale, 1.0, 1.0)
                    ..rotateY(rotateY),
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: opacity,
                    child: child,
                  ),
                );
              },
              child: child,
            );
          },
        );
}

/// Show a modal dialog with VisionOS 3D depth pop-up transition.
Future<T?> peekShow3DDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.12, 0.88, 0.22, 1.0),
      );
      final scale = 0.90 + (curvedAnimation.value * 0.10);
      final opacity = curvedAnimation.value.clamp(0.0, 1.0);

      return Transform(
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0006)
          ..scaleByDouble(scale, scale, 1.0, 1.0),
        alignment: Alignment.center,
        child: Opacity(
          opacity: opacity,
          child: child,
        ),
      );
    },
  );
}

/// Show a bottom sheet with 3D spring bounce transition.
Future<T?> peekShow3DSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor ?? Colors.transparent,
    isScrollControlled: isScrollControlled,
    builder: builder,
  );
}
