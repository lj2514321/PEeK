import 'package:embyplayer/src/core/presentation/peek_spring.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Hands the "a shared element is in the air" flag from the route transition
/// down to the page.
///
/// The destination page must keep its own copy of the artwork for layout but
/// stop painting it, otherwise the flight would reveal the finished poster
/// sitting in its slot from the first frame — which is exactly the "the page
/// just appeared" reading this transition exists to avoid. The flag is a
/// [ValueListenable] so only the poster slot rebuilds when it flips, not the
/// whole page, and it flips from the animation tick rather than from a build.
class PeekSharedFlight extends InheritedWidget {
  const PeekSharedFlight({
    super.key,
    required this.flying,
    required super.child,
  });

  final ValueListenable<bool> flying;

  static ValueListenable<bool>? flyingOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PeekSharedFlight>()?.flying;

  @override
  bool updateShouldNotify(PeekSharedFlight oldWidget) =>
      oldWidget.flying != flying;
}

/// Container (anchor) transformation for page pushes.
///
/// The pressed card's artwork is a shared element: it starts exactly on the
/// card's rectangle, travels to the rectangle the destination page reserved for
/// its own poster, and hands off to the page's copy on the same frame while the
/// page fades in around it.
///
/// Five earlier revisions of this file were wrong, and the reasons are worth
/// keeping:
///
/// 1. Clipping a page-sized child to a growing rectangle produced a fade, not a
///    morph: nothing inside the window moved.
/// 2. Growing the artwork to fill the *screen* landed it on the page's 16:9
///    backdrop, not on its poster — different asset, different shape, so the
///    poster visibly re-cropped at hand-off. The destination has to be the
///    poster slot, which is why the layout is now a shared pure function.
/// 3. A freshly built provider at another size decoded again and flashed a
///    placeholder. The flight now paints the same `PeekMediaImage` the grid
///    painted, so the frame is a synchronous cache hit.
/// 4. Re-laying the artwork out at every size repainted the image and its glow
///    on every frame. The flight paints at the *destination* size once and
///    moves it with a transform, so the raster is reused.
/// 5. A non-uniform transform is what makes both shapes meet, but it also
///    stretches the artwork. It only runs when the card and the slot really are
///    the same aspect ratio (the route checks), where the scale is uniform.
class PeekAnchorMorphTransition extends StatefulWidget {
  const PeekAnchorMorphTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.originRect,
    required this.destination,
    required this.child,
    this.poster,
  });

  /// Drives the flight, 0 = on the card, 1 = in the poster slot.
  final Animation<double> animation;

  /// Drives the recess of this page when another route is pushed on top.
  final Animation<double> secondaryAnimation;

  /// Global rectangle of the card that was pressed.
  final Rect originRect;

  /// Where the shared element lands, given the window size.
  final Rect Function(Size screen) destination;

  /// The card's artwork, normally the destination page's own poster widget.
  final Widget? poster;

  final Widget child;

  /// The shared element carries the motion, so this curve can be calm: 8% at
  /// 42 ms, 36% at 126 ms, 78% at half way.
  static const Curve morphCurve = Cubic(0.32, 0.0, 0.18, 1.0);

  /// The page fades in behind the flight. It starts almost immediately (the
  /// artwork leaves a hole in the grid that has to be covered) and is complete
  /// well before the flight lands, so the last third is the poster settling
  /// into a page that is already there.
  static const double pageFadeStart = 0.08;
  static const double pageFadeEnd = 0.62;

  /// How far this page recedes when another route is pushed on top of it.
  static const double recessScale = 0.03;

  @override
  State<PeekAnchorMorphTransition> createState() =>
      _PeekAnchorMorphTransitionState();
}

class _PeekAnchorMorphTransitionState extends State<PeekAnchorMorphTransition> {
  final ValueNotifier<bool> _flying = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_syncFlying);
    _syncFlying();
  }

  @override
  void didUpdateWidget(PeekAnchorMorphTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_syncFlying);
      widget.animation.addListener(_syncFlying);
      _syncFlying();
    }
  }

  @override
  void dispose() {
    widget.animation.removeListener(_syncFlying);
    _flying.dispose();
    super.dispose();
  }

  /// The page hides its poster for exactly as long as the flight is visible.
  void _syncFlying() {
    final flying = widget.animation.value < 0.999;
    if (_flying.value != flying) _flying.value = flying;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final destination = widget.destination(constraints.biggest);

        return AnimatedBuilder(
          animation: Listenable.merge([
            widget.animation,
            widget.secondaryAnimation,
          ]),
          builder: (context, child) {
            final raw = widget.animation.value.clamp(0.0, 1.0);
            final recess = PeekCurves.depthRecess.transform(
              widget.secondaryAnimation.value.clamp(0.0, 1.0),
            );

            // Settled and nothing on top: hand the page back with no extra
            // layers, so the steady state costs what it did before.
            if (raw >= 0.999 && recess <= 0.001) return child!;

            final flying = raw < 0.999;
            final page = _pageLayer(child!, raw);
            final content = Transform.scale(
              scale: 1 - PeekAnchorMorphTransition.recessScale * recess,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  page,
                  if (flying && widget.poster != null)
                    Positioned.fromRect(
                      rect: destination,
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: Transform(
                            alignment: Alignment.center,
                            transform: _flight(
                              origin: widget.originRect,
                              destination: destination,
                              t: PeekAnchorMorphTransition.morphCurve.transform(
                                raw,
                              ),
                            ),
                            child: widget.poster,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );

            if (recess <= 0.001) return content;
            return Stack(
              fit: StackFit.expand,
              children: [
                content,
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.30 * recess),
                  ),
                ),
              ],
            );
          },
          child: PeekSharedFlight(flying: _flying, child: widget.child),
        );
      },
    );
  }

  Widget _pageLayer(Widget child, double raw) {
    final t =
        ((raw - PeekAnchorMorphTransition.pageFadeStart) /
                (PeekAnchorMorphTransition.pageFadeEnd -
                    PeekAnchorMorphTransition.pageFadeStart))
            .clamp(0.0, 1.0);
    final opacity = t * t * (3 - 2 * t);
    if (opacity >= 0.999) return child;
    return Opacity(opacity: opacity, child: child);
  }

  /// Transform that maps the destination-sized artwork back onto the card.
  ///
  /// The artwork is laid out once at [destination] and only moved afterwards:
  /// the scale is uniform whenever the two rectangles share an aspect ratio,
  /// which the route guarantees before choosing this transition.
  Matrix4 _flight({
    required Rect origin,
    required Rect destination,
    required double t,
  }) {
    final scaleX = _lerp(origin.width / destination.width, 1.0, t);
    final scaleY = _lerp(origin.height / destination.height, 1.0, t);
    final dx = _lerp(origin.center.dx - destination.center.dx, 0.0, t);
    final dy = _lerp(origin.center.dy - destination.center.dy, 0.0, t);
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scaleX, scaleY, 1, 1);
  }

  static double _lerp(double from, double to, double t) =>
      from + (to - from) * t;
}
