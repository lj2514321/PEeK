import 'dart:ui' as ui;

import 'package:embyplayer/src/app/theme.dart';
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
    this.routeAnimation,
    this.scrollOffset,
    required super.child,
  });

  /// Global notifier holding the token of the source card whose artwork is
  /// currently in flight, so the source grid card can hide its own copy and
  /// leave a clean slot until the reverse flight lands back on it.
  static final ValueNotifier<Object?> activeCardToken = ValueNotifier<Object?>(
    null,
  );

  final ValueListenable<bool> flying;
  final Animation<double>? routeAnimation;
  final ValueNotifier<double>? scrollOffset;

  static ValueListenable<bool>? flyingOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PeekSharedFlight>()?.flying;

  static Animation<double>? routeAnimationOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PeekSharedFlight>()
      ?.routeAnimation;

  static ValueNotifier<double>? scrollOffsetOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PeekSharedFlight>()
      ?.scrollOffset;

  @override
  bool updateShouldNotify(PeekSharedFlight oldWidget) =>
      oldWidget.flying != flying ||
      oldWidget.routeAnimation != routeAnimation ||
      oldWidget.scrollOffset != scrollOffset;
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
    this.source,
    this.originCardToken,
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

  /// The artwork the pressed card was already showing. When the card drew a
  /// different asset than the page's poster (a 16:9 still), the flight blends
  /// the two: the source is whole at the start and gone at the end, so neither
  /// end has to swap the picture in one frame.
  final Widget? source;

  /// Optional identity token of the pressed card so the source grid can hide
  /// the stationary copy while the shared poster is in flight.
  final Object? originCardToken;

  final Widget child;

  /// Forward curve for the container & shared poster bursting out of the card.
  static const Curve morphCurve = Cubic(0.22, 0.86, 0.24, 1.0);

  /// Reverse curve (applied to `1 - raw`) so collapse starts immediately on
  /// Back and decelerates softly onto the source card.
  static const Curve reverseMorphCurve = Cubic(0.22, 0.68, 0.18, 1.0);

  /// Curve for the page container expanding out of [originRect] to full window.
  static const Curve containerCurve = Cubic(0.22, 0.86, 0.24, 1.0);

  /// Fraction of the transition by which the container clip reaches full window.
  static const double containerExpandEnd = 0.72;

  /// Starting corner radius of the expanding container clip.
  static const double containerStartRadius = AppRadius.value;

  /// The page fades in behind the flight. It starts almost immediately (the
  /// artwork leaves a hole in the grid that has to be covered) and is complete
  /// well before the flight lands, so the last third is the poster settling
  /// into a page that is already there.
  static const double pageFadeStart = 0.08;
  static const double pageFadeEnd = 0.62;

  /// Maximum scroll offset on the detail page before reverse pop suppresses
  /// the poster flight (since the hero poster has scrolled offscreen).
  static const double maxReverseFlightScrollOffset = 280.0;

  /// Where the hand-off starts. From here the page's poster is painted under
  /// the flyer and the flyer fades out over the last tenth of the flight.
  /// Swapping the two in one frame makes every difference between them jump:
  /// the residual crop of a card that was not 2:3, and the halo and shadow the
  /// flyer does not carry.
  static const double handOffStart = 0.90;

  /// How far this page recedes when another route is pushed on top of it.
  static const double recessScale = 0.03;

  @override
  State<PeekAnchorMorphTransition> createState() =>
      _PeekAnchorMorphTransitionState();
}

class _PeekAnchorMorphTransitionState extends State<PeekAnchorMorphTransition> {
  final ValueNotifier<bool> _flying = ValueNotifier<bool>(false);
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);

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
    final token = widget.originCardToken;
    if (token != null && PeekSharedFlight.activeCardToken.value == token) {
      PeekSharedFlight.activeCardToken.value = null;
    }
    _flying.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  bool get _isReverseScrolledOut =>
      widget.animation.status == AnimationStatus.reverse &&
      _scrollOffset.value >
          PeekAnchorMorphTransition.maxReverseFlightScrollOffset;

  /// The page hides its poster for exactly as long as the flight is visible.
  void _syncFlying() {
    final raw = widget.animation.value;
    // Forward: the page's own poster is painted from `handOffStart` on,
    // underneath the flyer, so the flyer can dissolve into it instead of being
    // swapped for it in a single frame.
    //
    // Backward: the flyer must carry the *whole* retract. Showing the page's
    // poster instead leaves the poster at full size while the container clip
    // closes in on it, so it gets cropped back into the card instead of shrunk
    // into it.
    final handOff = widget.animation.status != AnimationStatus.reverse;
    final flying =
        raw < (handOff ? PeekAnchorMorphTransition.handOffStart : 0.999) &&
        !_isReverseScrolledOut;
    if (_flying.value != flying) _flying.value = flying;

    final token = widget.originCardToken;
    if (token != null) {
      final activeInAir =
          flying &&
          widget.poster != null &&
          (raw > 0.001 || widget.animation.status == AnimationStatus.forward);
      if (activeInAir && PeekSharedFlight.activeCardToken.value != token) {
        PeekSharedFlight.activeCardToken.value = token;
      } else if (!activeInAir &&
          PeekSharedFlight.activeCardToken.value == token) {
        PeekSharedFlight.activeCardToken.value = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        final baseDestination = widget.destination(screen);

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

            // Settled and nothing on top: every layer below is already a no-op
            // by value (opacity 1 skips its save layer, `Clip.none` skips the
            // clip, a transparent scrim paints nothing), so the shape is kept.
            // It used to return the bare child here, and that changed the
            // widget type at this position — which re-inflates the whole detail
            // page at hand-off, measured as a 19 ms build frame on every open.
            final isReverse =
                widget.animation.status == AnimationStatus.reverse;
            final e = isReverse
                ? 1.0 -
                      PeekAnchorMorphTransition.reverseMorphCurve.transform(
                        1.0 - raw,
                      )
                : PeekAnchorMorphTransition.morphCurve.transform(raw);
            final startRadius = widget.originRect.width < 100
                ? 12.0
                : AppRadius.value;
            final radius =
                ui.lerpDouble(startRadius, AppRadius.value, e) ??
                AppRadius.value;
            final fullRect = Offset.zero & screen;
            final currentRect =
                Rect.lerp(widget.originRect, fullRect, e) ?? fullRect;

            final flying = raw < 0.999 && !_isReverseScrolledOut;
            final destination = _scrollOffset.value > 0.5
                ? baseDestination.shift(Offset(0, -_scrollOffset.value))
                : baseDestination;
            final page = _pageLayer(
              child!,
              raw: raw,
              e: e,
              radius: radius,
              isReverse: isReverse,
            );
            final content = Transform.scale(
              scale: 1 - PeekAnchorMorphTransition.recessScale * recess,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (e < 0.999)
                    IgnorePointer(
                      key: const ValueKey('anchor-scrim'),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.44 * e),
                      ),
                    ),
                  if (e < 0.85)
                    Positioned.fromRect(
                      key: const ValueKey('anchor-shadow'),
                      rect: currentRect,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(radius),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: 0.55 * (1.0 - e),
                                ),
                                blurRadius: 20,
                                spreadRadius: 1,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  KeyedSubtree(key: const ValueKey('anchor-page'), child: page),
                  if (e < 0.85)
                    Positioned.fromRect(
                      key: const ValueKey('anchor-border'),
                      rect: currentRect,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(radius),
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: 0.35 * (1.0 - e),
                              ),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (flying && widget.poster != null)
                    _buildFlyingPoster(destination: destination, e: e),
                ],
              ),
            );

            // Always the same shape. A transparent scrim and a `Transform` at
            // scale 1 cost nothing; a missing child costs the page its element.
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
          child: PeekSharedFlight(
            flying: _flying,
            routeAnimation: widget.animation,
            scrollOffset: _scrollOffset,
            child: widget.child,
          ),
        );
      },
    );
  }

  Widget _pageLayer(
    Widget child, {
    required double raw,
    required double e,
    required double radius,
    required bool isReverse,
  }) {
    final fadeStart = isReverse
        ? 0.05
        : PeekAnchorMorphTransition.pageFadeStart;
    final fadeEnd = isReverse ? 0.42 : PeekAnchorMorphTransition.pageFadeEnd;
    final t = ((raw - fadeStart) / (fadeEnd - fadeStart)).clamp(0.0, 1.0);
    final opacity = t * t * (3 - 2 * t);

    // Same shape at every value: `Opacity(1)` and `Clip.none` are free, while
    // swapping this subtree for the bare child re-inflated the page — the whole
    // detail page, measured at 19 ms — on the frame the flight landed.
    return ClipRRect(
      clipper: _AnchorContainerClipper(
        origin: widget.originRect,
        progress: e,
        radius: radius,
      ),
      clipBehavior: e >= 0.999 ? Clip.none : Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF0A0E17)),
          Opacity(opacity: opacity, child: child),
        ],
      ),
    );
  }

  /// The flying artwork: the card's own asset on top at the start, the page's
  /// poster on top at the end.
  Widget _artwork({required double blend}) {
    final poster = widget.poster;
    final source = widget.source;
    if (source == null || poster == null) return poster ?? source!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: 1 - blend, child: source),
        Opacity(opacity: blend, child: poster),
      ],
    );
  }

  Widget _buildFlyingPoster({required Rect destination, required double e}) {
    // Uniform scale, always. The flyer used to be laid out in a frame that
    // lerped between the card's rectangle and the poster's, and `BoxFit.cover`
    // answered the changing aspect by cropping: the artwork stayed cropped for
    // the entire flight and could only become whole on the frame the flight
    // ended, which is the snap that made the poster look like it was changing.
    //
    // Instead the frame is always the destination and only its scale and centre
    // travel: from the largest even scale that fits inside the pressed widget
    // (`contain`, so nothing is ever cut) to exactly 1.0 at the slot.
    final origin = widget.originRect;
    final fitWidth = destination.width <= 0
        ? 1.0
        : origin.width / destination.width;
    final fitHeight = destination.height <= 0
        ? 1.0
        : origin.height / destination.height;
    final startScale = (fitWidth < fitHeight ? fitWidth : fitHeight).clamp(
      0.05,
      1.0,
    );
    final scale = startScale + (1 - startScale) * e;
    final center =
        Offset.lerp(origin.center, destination.center, e) ?? destination.center;
    final frame = Rect.fromCenter(
      center: center,
      width: destination.width,
      height: destination.height,
    );

    // The artwork the card was showing fades into the page's poster across the
    // middle of the flight. When both ends are the same picture this does
    // nothing; when they are different assets (a 16:9 still becoming a poster)
    // it is the only way neither end has to swap the picture in one frame.
    final rawBlend = ((e - 0.10) / 0.58).clamp(0.0, 1.0);
    final blend = rawBlend * rawBlend * (3 - 2 * rawBlend);

    // Forward only: the dissolve exists to hide the hand-off, and on the way
    // back there is nothing to dissolve into — the flyer stays solid until it
    // lands on the card.
    final dissolve = widget.animation.status == AnimationStatus.reverse
        ? 0.0
        : ((e - PeekAnchorMorphTransition.handOffStart) /
                  (1 - PeekAnchorMorphTransition.handOffStart))
              .clamp(0.0, 1.0);

    return Positioned.fromRect(
      key: const Key('flying-poster-box'),
      rect: frame,
      child: IgnorePointer(
        child: Opacity(
          opacity: 1 - dissolve,
          child: Transform.scale(
            scale: scale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.value),
              child: RepaintBoundary(
                child: SizedBox(
                  width: destination.width,
                  height: destination.height,
                  child: _artwork(blend: blend),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnchorContainerClipper extends CustomClipper<RRect> {
  const _AnchorContainerClipper({
    required this.origin,
    required this.progress,
    required this.radius,
  });

  final Rect origin;
  final double progress;
  final double radius;

  @override
  RRect getClip(Size size) {
    final full = Offset.zero & size;
    if (progress >= 0.999) {
      return RRect.fromRectAndRadius(full, Radius.circular(radius));
    }
    final rect = Rect.lerp(origin, full, progress) ?? full;
    return RRect.fromRectAndRadius(rect, Radius.circular(radius));
  }

  @override
  bool shouldReclip(_AnchorContainerClipper oldClipper) =>
      oldClipper.progress != progress ||
      oldClipper.origin != origin ||
      oldClipper.radius != radius;
}
