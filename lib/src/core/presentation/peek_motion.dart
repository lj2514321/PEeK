import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_cascading_sheet.dart';
import 'package:embyplayer/src/core/presentation/peek_spring.dart';
import 'package:flutter/material.dart';

export 'package:embyplayer/src/core/presentation/peek_cascading_sheet.dart';
export 'package:embyplayer/src/core/presentation/peek_magnetic_button.dart';
export 'package:embyplayer/src/core/presentation/peek_spring.dart';

/// Keeps every visited destination mounted while animating opacity, subtle scale,
/// and a small composited directional translation between the active pages.
///
/// This avoids media-library reloads and layout animation jank while still
/// giving top-level navigation a clear sense of direction and physical depth.
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
    final curve = widget.active
        ? PeekCurves.spatialEnter
        : PeekCurves.depthRecess;

    return Offstage(
      offstage: _offstage,
      child: AnimatedSlide(
        offset: widget.offset,
        duration: duration,
        curve: curve,
        child: AnimatedScale(
          scale: widget.active ? 1.0 : 0.95,
          duration: duration,
          curve: curve,
          child: AnimatedOpacity(
            opacity: widget.active ? 1.0 : 0.0,
            duration: duration,
            curve: curve,
            onEnd: () {
              if (!widget.active && mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!widget.active && mounted) {
                    setState(() => _offstage = true);
                  }
                });
              }
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Signature 3D Spatial Depth Page Route with dual-layer depth recess.
///
/// When pushed, the incoming route drops into place smoothly using [PeekCurves.spatialEnter]
/// while the underlying route recedes into the background via [secondaryAnimation]
/// (`scale: 1.0 -> 0.925` and subtle ambient dimming).
/// On pop, the underlying page surfaces back to the foreground seamlessly.
class PeekSpatialPageRoute<T> extends PageRouteBuilder<T> {
  PeekSpatialPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.transitionDuration = const Duration(milliseconds: 340),
    super.reverseTransitionDuration = const Duration(milliseconds: 260),
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (AppMotion.isTest) return child;

           final enterCurved = CurvedAnimation(
             parent: animation,
             curve: PeekCurves.spatialEnter,
             reverseCurve: Curves.easeInQuad,
           );

           final secCurved = CurvedAnimation(
             parent: secondaryAnimation,
             curve: PeekCurves.depthRecess,
             reverseCurve: PeekCurves.spatialEnter,
           );

           final current = SlideTransition(
             position: Tween<Offset>(
               begin: const Offset(0.035, 0.0),
               end: Offset.zero,
             ).animate(enterCurved),
             child: FadeTransition(
               opacity: enterCurved,
               child: RepaintBoundary(child: child),
             ),
           );

           return AnimatedBuilder(
             animation: secCurved,
             builder: (context, currentChild) {
               final secVal = secCurved.value;
               if (secVal <= 0.001) return currentChild!;

               return Stack(
                 fit: StackFit.expand,
                 children: [
                   currentChild!,
                   IgnorePointer(
                     child: ColoredBox(
                       color: Colors.black.withValues(alpha: secVal * 0.35),
                     ),
                   ),
                 ],
               );
             },
             child: current,
           );
         },
       );
}

/// Backwards-compatible alias for [PeekSpatialPageRoute].
typedef Peek3DPageRoute<T> = PeekSpatialPageRoute<T>;

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
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (AppMotion.isTest) return child;

           final enterCurved = CurvedAnimation(
             parent: animation,
             curve: PeekCurves.spatialEnter,
             reverseCurve: Curves.easeInQuad,
           );

           final secCurved = CurvedAnimation(
             parent: secondaryAnimation,
             curve: PeekCurves.depthRecess,
             reverseCurve: PeekCurves.spatialEnter,
           );

           final current = SlideTransition(
             position: Tween<Offset>(
               begin: const Offset(0.03, 0.0),
               end: Offset.zero,
             ).animate(enterCurved),
             child: FadeTransition(
               opacity: enterCurved,
               child: RepaintBoundary(child: child),
             ),
           );

           return AnimatedBuilder(
             animation: secCurved,
             builder: (context, currentChild) {
               final secVal = secCurved.value;
               if (secVal <= 0.001) return currentChild!;

               return Stack(
                 fit: StackFit.expand,
                 children: [
                   currentChild!,
                   IgnorePointer(
                     child: ColoredBox(
                       color: Colors.black.withValues(alpha: secVal * 0.30),
                     ),
                   ),
                 ],
               );
             },
             child: current,
           );
         },
       );
}

/// Cinema Theater Mode Page Route for entering full-screen media playback.
///
/// Features a theatrical curtain dissolve into pitch black, gentle aperture expansion,
/// and zero distracting chrome jumps.
class TheatricalIrisPageRoute<T> extends PageRouteBuilder<T> {
  TheatricalIrisPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.transitionDuration = const Duration(milliseconds: 380),
    super.reverseTransitionDuration = const Duration(milliseconds: 280),
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (AppMotion.isTest) return child;

           final enterCurved = CurvedAnimation(
             parent: animation,
             curve: PeekCurves.cinemaFade,
             reverseCurve: Curves.easeInQuad,
           );

           final secCurved = CurvedAnimation(
             parent: secondaryAnimation,
             curve: PeekCurves.depthRecess,
             reverseCurve: PeekCurves.spatialEnter,
           );

           final current = ColoredBox(
             color: Colors.black,
             child: FadeTransition(
               opacity: enterCurved,
               child: RepaintBoundary(child: child),
             ),
           );

           return AnimatedBuilder(
             animation: secCurved,
             builder: (context, currentChild) {
               final secVal = secCurved.value;
               if (secVal <= 0.001) return currentChild!;

               return Stack(
                 fit: StackFit.expand,
                 children: [
                   currentChild!,
                   IgnorePointer(
                     child: ColoredBox(
                       color: Colors.black.withValues(alpha: secVal * 0.5),
                     ),
                   ),
                 ],
               );
             },
             child: current,
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
    barrierColor: const Color(0xB8000000),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (AppMotion.isTest) return child;
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: PeekCurves.spatialEnter,
      );
      final scale = 0.94 + (curvedAnimation.value * 0.06);
      final opacity = curvedAnimation.value.clamp(0.0, 1.0);

      return Transform.scale(
        scale: scale,
        child: Opacity(opacity: opacity, child: child),
      );
    },
  );
}

/// Shows a bottom sheet panel with velvety spring slide transition and cascading depth awareness.
Future<T?> peekShowSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = true,
  ShapeBorder? shape,
  double? elevation,
  Clip? clipBehavior,
  bool barrierDismissible = true,
}) {
  if (AppMotion.isTest) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: backgroundColor ?? Colors.transparent,
      elevation: elevation ?? 0,
      shape: shape ?? const RoundedRectangleBorder(side: BorderSide.none),
      clipBehavior: clipBehavior ?? Clip.none,
      isScrollControlled: isScrollControlled,
      isDismissible: barrierDismissible,
      builder: builder,
    );
  }

  return Navigator.of(context).push<T>(
    PeekCascadingSheetRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}
