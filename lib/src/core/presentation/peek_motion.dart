import 'dart:async';

import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_cascading_sheet.dart';
import 'package:embyplayer/src/core/presentation/peek_spring.dart';
import 'package:flutter/material.dart';

export 'package:embyplayer/src/core/presentation/peek_cascading_sheet.dart';
export 'package:embyplayer/src/core/presentation/peek_magnetic_button.dart';
export 'package:embyplayer/src/core/presentation/peek_spring.dart';

/// Tracks the last pointer-down screen alignment so that [PeekSpatialPageRoute]
/// and modal transitions can morph directly out of (and shrink back into) the
/// exact card or button coordinate the user clicked.
abstract final class PeekMotionOrigin {
  static Alignment _lastTapAlignment = Alignment.center;

  static Alignment get lastTapAlignment => _lastTapAlignment;

  static void recordTap(BuildContext context, Offset globalPosition) {
    final size = MediaQuery.maybeSizeOf(context);
    if (size == null || size.width <= 0 || size.height <= 0) return;
    final ax = ((globalPosition.dx / size.width) * 2.0 - 1.0).clamp(
      -0.84,
      0.84,
    );
    final ay = ((globalPosition.dy / size.height) * 2.0 - 1.0).clamp(
      -0.84,
      0.84,
    );
    _lastTapAlignment = Alignment(ax, ay);
  }
}

/// Broadcasts an incrementing [activationEpoch] whenever a destination tab
/// transitions from inactive to active inside [PeekIndexedTransitionStack],
/// allowing child [PeekStaggeredGridItem]s to replay their 2D wave choreography
/// even when the destination widget tree is kept alive.
class PeekTabTransitionScope extends InheritedWidget {
  const PeekTabTransitionScope({
    super.key,
    required this.activationEpoch,
    required super.child,
  });

  final int activationEpoch;

  static int? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PeekTabTransitionScope>()
        ?.activationEpoch;
  }

  @override
  bool updateShouldNotify(PeekTabTransitionScope oldWidget) =>
      oldWidget.activationEpoch != activationEpoch;
}

/// 2D Wave Staggered Choreography wrapper for grid and rail items.
///
/// Ripples items in along a diagonal wave (`row * 44ms + col * 26ms`) with
/// optical rack-focus (`blur 6.5px -> 0px`), spring lift (`28px -> 0px`),
/// and spring scale (`0.88 -> 1.015 -> 1.0`).
/// Automatically replays when its enclosing tab is re-entered via [PeekTabTransitionScope],
/// and unwraps all transform/filter layers once settled for zero scroll overhead.
class PeekStaggeredGridItem extends StatefulWidget {
  const PeekStaggeredGridItem({
    super.key,
    required this.index,
    required this.columns,
    required this.child,
    this.horizontal = false,
  });

  final int index;
  final int columns;
  final Widget child;
  final bool horizontal;

  @override
  State<PeekStaggeredGridItem> createState() => _PeekStaggeredGridItemState();
}

class _PeekStaggeredGridItemState extends State<PeekStaggeredGridItem>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _delayTimer;
  bool _settled = false;
  int? _lastEpoch;
  int _waveToken = 0;

  @override
  void initState() {
    super.initState();
    if (AppMotion.isTest) {
      _settled = true;
      return;
    }

    final controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 560),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _settled = true);
          }
        });
    _controller = controller;
    _triggerStaggeredWave(fromInit: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.isTest) return;
    final epoch = PeekTabTransitionScope.maybeOf(context);
    if (_lastEpoch != null && epoch != null && epoch != _lastEpoch) {
      _triggerStaggeredWave(tabReplay: true);
    }
    _lastEpoch = epoch;
  }

  @override
  void didUpdateWidget(covariant PeekStaggeredGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (AppMotion.isTest) return;
    if (oldWidget.columns != widget.columns) {
      _triggerStaggeredWave();
    }
  }

  void _triggerStaggeredWave({bool fromInit = false, bool tabReplay = false}) {
    final controller = _controller;
    if (controller == null) return;

    _delayTimer?.cancel();
    final token = ++_waveToken;

    final batchIndex = widget.horizontal ? widget.index : (widget.index % 60);
    final maxAnimated = widget.horizontal ? 14 : 42;
    if (batchIndex >= maxAnimated) {
      _settled = true;
      controller.value = 1.0;
      if (!fromInit && mounted) {
        setState(() {});
      }
      return;
    }

    _settled = false;
    controller.stop();
    controller.value = 0.0;
    if (!fromInit && mounted) {
      setState(() {});
    }

    final cols = widget.columns < 1 ? 1 : widget.columns;
    final leadInMs = tabReplay ? 55 : (fromInit ? 45 : 0);
    final int delayMs;
    if (widget.horizontal) {
      delayMs = leadInMs + (batchIndex.clamp(0, 13) * 52).clamp(0, 480);
    } else {
      final row = batchIndex ~/ cols;
      final col = batchIndex % cols;
      delayMs = leadInMs + ((row * 78) + (col * 52)).clamp(0, 620);
    }

    // Start the stagger timer only after the synchronous layout/paint frame
    // completes so heavy shrinkWrap grids never swallow the cascade delays.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _waveToken) return;
      if (delayMs <= 0) {
        controller.forward(from: 0.0);
      } else {
        _delayTimer = Timer(Duration(milliseconds: delayMs), () {
          if (mounted && token == _waveToken) {
            controller.forward(from: 0.0);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_settled ||
        AppMotion.isTest ||
        _controller == null ||
        MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, child) {
        final raw = _controller!.value;
        if (raw >= 0.999) return child!;
        if (raw <= 0.001) {
          return Opacity(opacity: 0.0, child: IgnorePointer(child: child));
        }

        final t = const Cubic(0.22, 1.22, 0.36, 1.0).transform(raw);
        final opacity = Curves.easeOutCubic.transform(
          (raw * 2.4).clamp(0.0, 1.0),
        );
        final scale = 0.80 + (0.20 * t);
        final offset = (1.0 - t) * (widget.horizontal ? 44.0 : 54.0);
        final dx = widget.horizontal ? offset : 0.0;
        final dy = widget.horizontal ? 0.0 : offset;
        final tiltX = widget.horizontal
            ? 0.0
            : (1.0 - raw) * (1.0 - raw) * 0.14;

        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..translateByDouble(dx, dy, 0.0, 1.0)
          ..scaleByDouble(scale, scale, 1.0, 1.0);
        if (tiltX > 0.001) {
          matrix.rotateX(tiltX);
        }

        return Transform(
          transform: matrix,
          alignment: Alignment.bottomCenter,
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: RepaintBoundary(child: widget.child),
    );
  }
}

/// Optical Blur-Dissolve + Micro-Depth Stack for top-level navigation.
///
/// Combines camera rack-focus (`ImageFilter.blur` 12px -> 0px while animating),
/// subtle directional drift (`18px -> 0px`), and `0.968 -> 1.0` depth condensation,
/// while broadcasting [PeekTabTransitionScope] so child grids cascade in on every switch.
class PeekIndexedTransitionStack extends StatefulWidget {
  const PeekIndexedTransitionStack({
    super.key,
    required this.index,
    required this.children,
  }) : assert(children.length > 0),
       assert(index >= 0 && index < children.length);

  final int index;
  final List<Widget> children;

  @override
  State<PeekIndexedTransitionStack> createState() =>
      _PeekIndexedTransitionStackState();
}

class _PeekIndexedTransitionStackState
    extends State<PeekIndexedTransitionStack> {
  late int _previousIndex;
  int _direction = 1;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.index;
  }

  @override
  void didUpdateWidget(PeekIndexedTransitionStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _previousIndex = oldWidget.index;
      _direction = widget.index > _previousIndex ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enterDuration = AppMotion.responsive(
      context,
      const Duration(milliseconds: 420),
    );
    final exitDuration = AppMotion.responsive(
      context,
      const Duration(milliseconds: 220),
    );

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (
            var childIndex = 0;
            childIndex < widget.children.length;
            childIndex++
          )
            _DestinationMotionLayer(
              key: ValueKey('peek-destination-$childIndex'),
              active: childIndex == widget.index,
              direction: _direction,
              enterDuration: enterDuration,
              exitDuration: exitDuration,
              child: widget.children[childIndex],
            ),
        ],
      ),
    );
  }
}

class _DestinationMotionLayer extends StatefulWidget {
  const _DestinationMotionLayer({
    super.key,
    required this.active,
    required this.direction,
    required this.enterDuration,
    required this.exitDuration,
    required this.child,
  });

  final bool active;
  final int direction;
  final Duration enterDuration;
  final Duration exitDuration;
  final Widget child;

  @override
  State<_DestinationMotionLayer> createState() =>
      _DestinationMotionLayerState();
}

class _DestinationMotionLayerState extends State<_DestinationMotionLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late bool _offstage;
  double _inactiveDy = 18.0;
  double _inactiveScale = 0.968;
  int _activationEpoch = 0;

  @override
  void initState() {
    super.initState();
    _offstage = !widget.active;
    _controller = AnimationController(
      vsync: this,
      value: widget.active ? 1.0 : 0.0,
      duration: widget.enterDuration,
      reverseDuration: widget.exitDuration,
    )..addStatusListener(_handleStatusChanged);
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.active && mounted) {
      setState(() => _offstage = true);
    }
  }

  @override
  void didUpdateWidget(_DestinationMotionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.enterDuration;
    _controller.reverseDuration = widget.exitDuration;

    if (widget.active == oldWidget.active) return;

    if (AppMotion.isTest || widget.enterDuration == Duration.zero) {
      _offstage = !widget.active;
      _controller.value = widget.active ? 1.0 : 0.0;
      return;
    }

    if (widget.active) {
      _activationEpoch++;
      _inactiveDy = widget.direction >= 0 ? 18.0 : -18.0;
      _inactiveScale = 0.968;
      _offstage = false;
      _controller.forward(from: 0.0);
    } else {
      _inactiveDy = widget.direction >= 0 ? -14.0 : 14.0;
      _inactiveScale = 0.975;
      _controller.reverse(from: _controller.value.clamp(0.01, 1.0));
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleStatusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scopedChild = PeekTabTransitionScope(
      activationEpoch: _activationEpoch,
      child: RepaintBoundary(child: widget.child),
    );

    if (AppMotion.isTest || widget.enterDuration == Duration.zero) {
      return Offstage(
        offstage: !widget.active,
        child: IgnorePointer(ignoring: !widget.active, child: scopedChild),
      );
    }

    return Offstage(
      offstage: _offstage,
      child: IgnorePointer(
        ignoring: !widget.active,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final raw = _controller.value;
            if (raw >= 0.999 && widget.active) {
              return child!;
            }

            final t = widget.active
                ? const Cubic(0.26, 0.86, 0.24, 1.0).transform(raw)
                : Curves.easeOutCubic.transform(raw);
            final dy = _inactiveDy * (1.0 - t);
            final scale = _inactiveScale + ((1.0 - _inactiveScale) * t);
            final opacity = Curves.easeOutQuad.transform(
              (raw * 1.4).clamp(0.0, 1.0),
            );
            return Transform.translate(
              offset: Offset(0.0, dy),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: Opacity(opacity: opacity, child: child),
              ),
            );
          },
          child: scopedChild,
        ),
      ),
    );
  }
}

/// Origin-Anchored Container Morph Page Route.
///
/// Expands directly out of the screen coordinate where the user tapped
/// ([PeekMotionOrigin.lastTapAlignment]) from `scale: 0.44 -> 1.0` with
/// hardware-composited scale, opacity, and container card morphing.
/// When popped, smoothly shrinks right back into the originating card.
class PeekSpatialPageRoute<T> extends PageRouteBuilder<T> {
  PeekSpatialPageRoute({
    required WidgetBuilder builder,
    super.settings,
    Alignment? originAlignment,
    super.transitionDuration = const Duration(milliseconds: 420),
    super.reverseTransitionDuration = const Duration(milliseconds: 300),
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (AppMotion.isTest) return child;

           final anchor = originAlignment ?? PeekMotionOrigin.lastTapAlignment;

           return PeekSpatialTransition(
             animation: animation,
             secondaryAnimation: secondaryAnimation,
             originAlignment: anchor,
             child: child,
           );
         },
       );
}

/// Hardware-composited container morph transition for [PeekSpatialPageRoute].
class PeekSpatialTransition extends StatefulWidget {
  const PeekSpatialTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.originAlignment,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Alignment originAlignment;
  final Widget child;

  @override
  State<PeekSpatialTransition> createState() => _PeekSpatialTransitionState();
}

class _PeekSpatialTransitionState extends State<PeekSpatialTransition> {
  late final CurvedAnimation _enterCurved;
  late final CurvedAnimation _fadeCurved;
  late final CurvedAnimation _secCurved;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _secScaleAnimation;
  late final Animation<double> _secScrimAnimation;

  @override
  void initState() {
    super.initState();
    _enterCurved = CurvedAnimation(
      parent: widget.animation,
      curve: const Cubic(0.25, 1.05, 0.35, 1.0),
      reverseCurve: const Cubic(0.32, 0.0, 0.22, 1.0),
    );

    _fadeCurved = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0.0, 0.68, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.15, 1.0, curve: Curves.easeInCubic),
    );

    _secCurved = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: PeekCurves.depthRecess,
      reverseCurve: PeekCurves.spatialEnter,
    );

    _scaleAnimation =
        Tween<double>(begin: 0.44, end: 1.0).animate(_enterCurved);
    _secScaleAnimation =
        Tween<double>(begin: 1.0, end: 0.925).animate(_secCurved);
    _secScrimAnimation =
        Tween<double>(begin: 0.0, end: 0.48).animate(_secCurved);
  }

  @override
  void dispose() {
    _enterCurved.dispose();
    _fadeCurved.dispose();
    _secCurved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boundedChild = RepaintBoundary(child: widget.child);

    final morphedChild = AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        if (widget.animation.value >= 0.999) {
          return child!;
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(16.0),
          clipBehavior: Clip.antiAlias,
          child: child!,
        );
      },
      child: boundedChild,
    );

    final primary = ScaleTransition(
      scale: _scaleAnimation,
      alignment: widget.originAlignment,
      child: FadeTransition(
        opacity: _fadeCurved,
        child: morphedChild,
      ),
    );

    return AnimatedBuilder(
      animation: _secCurved,
      builder: (context, currentChild) {
        if (widget.secondaryAnimation.value <= 0.001) {
          return currentChild!;
        }
        return ScaleTransition(
          scale: _secScaleAnimation,
          alignment: Alignment.center,
          child: Stack(
            fit: StackFit.expand,
            children: [
              currentChild!,
              FadeTransition(
                opacity: _secScrimAnimation,
                child: const IgnorePointer(
                  child: ColoredBox(color: Colors.black),
                ),
              ),
            ],
          ),
        );
      },
      child: primary,
    );
  }
}

/// Backwards-compatible alias for [PeekSpatialPageRoute].
typedef Peek3DPageRoute<T> = PeekSpatialPageRoute<T>;

/// A smooth, high-fashion Shared-Axis Optical Morph Page Route.
class PeekPageRoute<T> extends PageRouteBuilder<T> {
  PeekPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.transitionDuration = const Duration(milliseconds: 310),
    super.reverseTransitionDuration = const Duration(milliseconds: 240),
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (AppMotion.isTest) return child;

           final enterCurved = CurvedAnimation(
             parent: animation,
             curve: const Cubic(0.19, 1.0, 0.22, 1.0),
             reverseCurve: Curves.easeInCubic,
           );

           final fadeCurved = CurvedAnimation(
             parent: animation,
             curve: const Interval(0.0, 0.72, curve: Curves.easeOutCubic),
             reverseCurve: Curves.easeInQuad,
           );

           final secCurved = CurvedAnimation(
             parent: secondaryAnimation,
             curve: PeekCurves.depthRecess,
             reverseCurve: PeekCurves.spatialEnter,
           );

           final current = SlideTransition(
             position: Tween<Offset>(
               begin: const Offset(0.024, 0.0),
               end: Offset.zero,
             ).animate(enterCurved),
             child: ScaleTransition(
               scale: Tween<double>(begin: 0.96, end: 1.0).animate(enterCurved),
               child: FadeTransition(
                 opacity: fadeCurved,
                 child: RepaintBoundary(child: child),
               ),
             ),
           );

           return AnimatedBuilder(
             animation: secCurved,
             builder: (context, currentChild) {
               final secVal = secCurved.value;
               if (secVal <= 0.001) return currentChild!;

               final recessScale = 1.0 - (secVal * 0.045);
               final recessDx = -14.0 * secVal;
               return Transform.translate(
                 offset: Offset(recessDx, 0.0),
                 child: Transform.scale(
                   scale: recessScale,
                   alignment: Alignment.center,
                   child: Stack(
                     fit: StackFit.expand,
                     children: [
                       currentChild!,
                       IgnorePointer(
                         child: ColoredBox(
                           color: Colors.black.withValues(alpha: secVal * 0.35),
                         ),
                       ),
                     ],
                   ),
                 ),
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
             child: ScaleTransition(
               scale: Tween<double>(begin: 0.94, end: 1.0).animate(enterCurved),
               child: FadeTransition(
                 opacity: enterCurved,
                 child: RepaintBoundary(child: child),
               ),
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
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (AppMotion.isTest) return child;
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: PeekCurves.springSnap,
        reverseCurve: Curves.easeInCubic,
      );
      final val = curvedAnimation.value;
      final scale = 0.88 + (val * 0.12);
      final dy = (1.0 - val) * 18.0;
      final opacity = animation.value.clamp(0.0, 1.0);

      return Transform.translate(
        offset: Offset(0.0, dy),
        child: Transform.scale(
          scale: scale,
          child: Opacity(opacity: opacity, child: child),
        ),
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
