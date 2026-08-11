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

/// Signature 3D Spatial Depth Page Route (for poster and artwork focal points).
class Peek3DPageRoute<T> extends PageRouteBuilder<T> {
  Peek3DPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.transitionDuration = const Duration(milliseconds: 360),
    super.reverseTransitionDuration = const Duration(milliseconds: 280),
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
                final scale = 0.94 + (value * 0.06);
                final rotateY = (1.0 - value) * 0.06;
                final opacity = value.clamp(0.0, 1.0);

                return Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0007)
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

/// A smooth, high-fashion macOS/iOS Shared-Axis Scale & Slide Page Route.
///
/// Combines subtle depth scale (`0.96 -> 1.0`), slight horizontal offset, and fluid fade.
class PeekPageRoute<T> extends PageRouteBuilder<T> {
  PeekPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.transitionDuration = const Duration(milliseconds: 320),
    super.reverseTransitionDuration = const Duration(milliseconds: 260),
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
                final scale = 0.96 + (value * 0.04);
                final slideX = (1.0 - value) * 20.0;
                final opacity = value.clamp(0.0, 1.0);

                return Transform.translate(
                  offset: Offset(slideX, 0),
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: child,
                    ),
                  ),
                );
              },
              child: child,
            );
          },
        );
}

/// Function aliases for smooth dialogs and sheets.
const peekShow3DDialog = peekShowDialog;
const peekShow3DSheet = peekShowSheet;

/// Shows a modal dialog with VisionOS frosted glass micro-bounce transition.
Future<T?> peekShowDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.12, 0.88, 0.22, 1.0),
      );
      final scale = 0.94 + (curvedAnimation.value * 0.06);
      final opacity = curvedAnimation.value.clamp(0.0, 1.0);

      return Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: child,
        ),
      );
    },
  );
}

/// Shows a bottom sheet panel with velvety spring slide transition.
Future<T?> peekShowSheet<T>({
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
