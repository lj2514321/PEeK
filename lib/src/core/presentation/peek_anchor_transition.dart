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

  /// Global notifier holding the opacity of the source card during flight (0.0 .. 1.0).
  ///
  /// Instead of abruptly popping visibility at the very end of the transition,
  /// the source card smoothly fades in while the flyer fades out DURING the morph flight,
  /// completing the handoff before the animation finishes.
  static final ValueNotifier<double> cardFlightOpacity = ValueNotifier<double>(
    1.0,
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
    this.originClipFractions = EdgeInsets.zero,
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

  /// When the origin card was partially clipped (e.g. at the edge of a horizontal rail),
  /// these fractional insets (0..1) define what was clipped out so that the flyer can
  /// smoothly retract to and expand from the exact visible ratio.
  final EdgeInsets originClipFractions;

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
      PeekSharedFlight.cardFlightOpacity.value = 1.0;
    }
    _flying.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  Rect get _visibleOriginRect {
    if (widget.originClipFractions == EdgeInsets.zero) {
      return widget.originRect;
    }
    final insets = widget.originClipFractions;
    final w = widget.originRect.width;
    final h = widget.originRect.height;
    return Rect.fromLTRB(
      widget.originRect.left + w * insets.left,
      widget.originRect.top + h * insets.top,
      widget.originRect.right - w * insets.right,
      widget.originRect.bottom - h * insets.bottom,
    );
  }

  /// When a card was partially clipped at an edge, the artwork inside aligns
  /// to the visible edge so that the visible portion is not shifted or squashed.
  Alignment get _edgeAlignment {
    final insets = widget.originClipFractions;
    if (insets == EdgeInsets.zero) return Alignment.center;
    final x = insets.right > 0.005 ? -1.0 : (insets.left > 0.005 ? 1.0 : 0.0);
    final y = insets.bottom > 0.005 ? -1.0 : (insets.top > 0.005 ? 1.0 : 0.0);
    return Alignment(x, y);
  }

  /// Computes the shape adaptation progress (0.0 = origin edge shape, 1.0 = destination full shape).
  ///
  /// Shape deformation progresses smoothly in coordination with the flight, allowing
  /// the flyer to travel distortion-free and finish shape adaptation before landing.
  double _computeShapeProgress({required double raw, required bool isReverse}) {
    if (widget.originClipFractions == EdgeInsets.zero) {
      return 1.0;
    }

    const double earlyCutoff = 0.35;

    if (isReverse) {
      // In retract: pop progress p goes 0.0 -> 1.0.
      // Shape adapts from 1.0 (destination) to 0.0 (origin edge ratio) in early stage (p in 0.0..0.35).
      // Fulfills: "不要在动画末期再适配形变，应该在前期".
      final p = (1.0 - raw).clamp(0.0, 1.0);
      final t = (p / earlyCutoff).clamp(0.0, 1.0);
      final curvedT = Curves.easeInOutCubic.transform(t);
      return 1.0 - curvedT;
    } else {
      // In expand: forward progress raw goes 0.0 -> 1.0.
      // Shape blooms from 0.0 (origin edge ratio) to 1.0 (destination) in early stage (raw in 0.0..0.35).
      final t = (raw / earlyCutoff).clamp(0.0, 1.0);
      final curvedT = Curves.easeInOutCubic.transform(t);
      return curvedT;
    }
  }

  /// Calculates the flying poster's bounding box where spatial movement follows [spatialE]
  /// and edge shape / aspect ratio adaptation completes early via [shapeE].
  Rect _computeFlyingFrame({
    required Rect destination,
    required double spatialE,
    required double shapeE,
  }) {
    final origin = _visibleOriginRect;
    if (widget.originClipFractions == EdgeInsets.zero) {
      return Rect.lerp(origin, destination, spatialE) ?? destination;
    }

    final height = ui.lerpDouble(origin.height, destination.height, spatialE)!;
    final originAspect = origin.width / origin.height;
    final destAspect = destination.width / destination.height;
    final currentAspect = ui.lerpDouble(originAspect, destAspect, shapeE)!;
    final width = height * currentAspect;

    final insets = widget.originClipFractions;
    final double left;
    if (insets.left > 0.005) {
      final right = ui.lerpDouble(origin.right, destination.right, spatialE)!;
      left = right - width;
    } else {
      left = ui.lerpDouble(origin.left, destination.left, spatialE)!;
    }

    final double top;
    if (insets.top > 0.005) {
      final bottom = ui.lerpDouble(
        origin.bottom,
        destination.bottom,
        spatialE,
      )!;
      top = bottom - height;
    } else {
      top = ui.lerpDouble(origin.top, destination.top, spatialE)!;
    }

    return Rect.fromLTWH(left, top, width, height);
  }

  /// The corners touching a clipped viewport edge remain flat (radius 0) at origin,
  /// and smoothly interpolate to full corner radius at destination via [shapeE].
  BorderRadius _flyingBorderRadius(double shapeE) {
    final insets = widget.originClipFractions;
    final baseRadius = AppRadius.value;
    if (insets == EdgeInsets.zero) {
      return BorderRadius.circular(baseRadius);
    }
    final tl = (insets.left > 0.005 || insets.top > 0.005)
        ? Radius.circular(ui.lerpDouble(0.0, baseRadius, shapeE)!)
        : Radius.circular(baseRadius);
    final bl = (insets.left > 0.005 || insets.bottom > 0.005)
        ? Radius.circular(ui.lerpDouble(0.0, baseRadius, shapeE)!)
        : Radius.circular(baseRadius);
    final tr = (insets.right > 0.005 || insets.top > 0.005)
        ? Radius.circular(ui.lerpDouble(0.0, baseRadius, shapeE)!)
        : Radius.circular(baseRadius);
    final br = (insets.right > 0.005 || insets.bottom > 0.005)
        ? Radius.circular(ui.lerpDouble(0.0, baseRadius, shapeE)!)
        : Radius.circular(baseRadius);

    return BorderRadius.only(
      topLeft: tl,
      bottomLeft: bl,
      topRight: tr,
      bottomRight: br,
    );
  }

  /// Computes the flying poster's opacity throughout the flight.
  ///
  /// In retract (isReverse):
  /// - Hand-off from page poster slot: raw in [0.90, 0.999]
  /// - Mid-flight morphing travel: fully opaque (raw in [0.20, 0.90])
  /// - Final smooth landing onto the origin card: fades out (raw in [0.02, 0.20]),
  ///   completing hand-off smoothly by raw=0.02 without any late jarring pop.
  double _computeFlyerOpacity({required double raw, required bool isReverse}) {
    if (isReverse) {
      if (raw <= 0.02) {
        return 0.0;
      }
      if (raw > 0.90) {
        final t = ((0.999 - raw) / (0.999 - 0.90)).clamp(0.0, 1.0);
        return t * t * (3 - 2 * t);
      }
      if (raw >= 0.20) {
        return 1.0;
      }
      final t = ((raw - 0.02) / (0.20 - 0.02)).clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    } else {
      if (raw < 0.90) {
        return 1.0;
      }
      final t = ((0.999 - raw) / (0.999 - 0.90)).clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }
  }

  /// Computes the source card's opacity while in flight.
  ///
  /// In retract (isReverse):
  /// - The source card smoothly fades in during morph (raw in [0.02, 0.20]),
  ///   reaching 100% full opacity by raw=0.02 well before the animation terminates.
  double _computeCardFlightOpacity({
    required double raw,
    required bool isReverse,
  }) {
    if (isReverse) {
      if (raw <= 0.02) return 1.0;
      if (raw >= 0.20) return 0.0;
      final t = ((0.20 - raw) / (0.20 - 0.02)).clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    } else {
      if (raw >= 0.24) return 0.0;
      final t = ((0.24 - raw) / 0.24).clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }
  }

  bool get _isReverseScrolledOut =>
      widget.animation.status == AnimationStatus.reverse &&
      _scrollOffset.value >
          PeekAnchorMorphTransition.maxReverseFlightScrollOffset;

  /// The page hides its poster for exactly as long as the flight is visible.
  void _syncFlying() {
    final raw = widget.animation.value;
    final isReverse = widget.animation.status == AnimationStatus.reverse;
    final flying = raw < 0.999 && !_isReverseScrolledOut;
    if (_flying.value != flying) _flying.value = flying;

    // The pressed card stays hidden while the flight is up, but cross-fades
    // smoothly during morph so that handoff is complete before the animation finishes.
    final token = widget.originCardToken;
    if (token != null) {
      final activeInAir =
          flying &&
          widget.poster != null &&
          (raw > 0.001 || widget.animation.status == AnimationStatus.forward);
      if (activeInAir) {
        if (PeekSharedFlight.activeCardToken.value != token) {
          PeekSharedFlight.activeCardToken.value = token;
        }
        final cardOpacity = _computeCardFlightOpacity(
          raw: raw,
          isReverse: isReverse,
        );
        if ((PeekSharedFlight.cardFlightOpacity.value - cardOpacity).abs() >
            0.005) {
          PeekSharedFlight.cardFlightOpacity.value = cardOpacity;
        }
      } else {
        if (PeekSharedFlight.activeCardToken.value == token) {
          PeekSharedFlight.activeCardToken.value = null;
        }
        if (PeekSharedFlight.cardFlightOpacity.value != 1.0) {
          PeekSharedFlight.cardFlightOpacity.value = 1.0;
        }
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
            final startRadius = _visibleOriginRect.width < 100
                ? 12.0
                : AppRadius.value;
            final radius =
                ui.lerpDouble(startRadius, AppRadius.value, e) ??
                AppRadius.value;
            final fullRect = Offset.zero & screen;
            final currentRect =
                Rect.lerp(_visibleOriginRect, fullRect, e) ?? fullRect;

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
                  if (!isReverse && e < 0.85)
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
                  if (!isReverse && e < 0.85)
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
                  if (flying &&
                      widget.poster != null &&
                      (!isReverse || raw > 0.02))
                    _buildFlyingPoster(
                      destination: destination,
                      spatialE: e,
                      shapeE: _computeShapeProgress(
                        raw: raw,
                        isReverse: isReverse,
                      ),
                      flyerOpacity: _computeFlyerOpacity(
                        raw: raw,
                        isReverse: isReverse,
                      ),
                      isReverse: isReverse,
                    ),
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
    // On the way back the page has to be gone before its container clip gets
    // small. The clip shrinks from the full window to the card, and every glyph
    // it crosses is sliced by a hard edge for a frame: text that is still fully
    // opaque under a moving clip is what reads as flicker, and once the window
    // is small enough the content *under* the page shows through the gaps.
    // So the fade leads the clip on the retract instead of trailing it.
    final fadeStart = isReverse
        ? 0.25
        : PeekAnchorMorphTransition.pageFadeStart;
    final fadeEnd = isReverse ? 0.85 : PeekAnchorMorphTransition.pageFadeEnd;
    final t = ((raw - fadeStart) / (fadeEnd - fadeStart)).clamp(0.0, 1.0);
    final opacity = t * t * (3 - 2 * t);

    // Same shape at every value: `Opacity(1)` and `Clip.none` are free, while
    // swapping this subtree for the bare child re-inflated the page — the whole
    // detail page, measured at 19 ms — on the frame the flight landed.
    if (isReverse && opacity <= 0.001) {
      return const SizedBox.shrink();
    }
    final clipper = isReverse
        ? null
        : _AnchorContainerClipper(
            origin: _visibleOriginRect,
            progress: e,
            radius: radius,
          );
    final content = Stack(
      fit: StackFit.expand,
      children: [
        if (!isReverse) const ColoredBox(color: Color(0xFF0A0E17)),
        Opacity(opacity: opacity, child: child),
      ],
    );
    if (clipper == null) {
      return content;
    }
    return ClipRRect(
      clipper: clipper,
      clipBehavior: e >= 0.999 ? Clip.none : Clip.antiAlias,
      child: content,
    );
  }

  Widget _buildFlyingPoster({
    required Rect destination,
    required double spatialE,
    required double shapeE,
    required double flyerOpacity,
    required bool isReverse,
  }) {
    if (flyerOpacity <= 0.001) {
      return const SizedBox.shrink();
    }

    // Spatial position follows spatialE; aspect ratio and edge flattening adapt
    // in the early stage via shapeE so that landing and travel are distortion-free.
    final frame = _computeFlyingFrame(
      destination: destination,
      spatialE: spatialE,
      shapeE: shapeE,
    );

    final double rawBlend;
    if (isReverse) {
      // In retract: spatialE goes from 1.0 down to 0.0.
      // The cross-fade ("渐变") completes DURING the morphing flight:
      // Starting from spatialE = 0.85 and completing at spatialE = 0.25 (blend = 0.0).
      // Fulfills: "渐变在形变过程中应该就完成了，而不是形变动画结束或即将结束再突然渐变".
      rawBlend = ((spatialE - 0.25) / (0.85 - 0.25)).clamp(0.0, 1.0);
    } else {
      rawBlend = ((spatialE - 0.15) / 0.52).clamp(0.0, 1.0);
    }
    final blend = rawBlend * rawBlend * (3 - 2 * rawBlend);

    Widget posterContent = ClipRRect(
      borderRadius: _flyingBorderRadius(shapeE),
      child: RepaintBoundary(
        child: _artwork(
          blend: blend,
          destination: destination,
          frame: frame,
          alignment: _edgeAlignment,
          wide: widget.originRect.width > widget.originRect.height,
          shapeE: shapeE,
        ),
      ),
    );

    if (flyerOpacity < 0.999) {
      posterContent = Opacity(
        opacity: flyerOpacity.clamp(0.0, 1.0),
        child: posterContent,
      );
    }

    return Positioned.fromRect(
      key: const Key('flying-poster-box'),
      rect: frame,
      child: IgnorePointer(child: posterContent),
    );
  }

  /// The flying artwork.
  ///
  /// The two pieces are laid out differently on purpose. The page's poster is
  /// laid out at the poster slot's size and scaled to fill the frame, so it is
  /// exact on the frame the flight ends. The card's own still has to be exact on
  /// the frame the flight *starts*. When the origin card was clipped at an edge,
  /// the source still is laid out with its full unclipped width and offset so the
  /// visible portion matches the edge card exactly without centering distortion.
  Widget _artwork({
    required double blend,
    required Rect destination,
    required Rect frame,
    required Alignment alignment,
    required bool wide,
    required double shapeE,
  }) {
    final poster = widget.poster;
    final source = widget.source;
    if (source == null || poster == null || !wide) {
      return FittedBox(
        fit: BoxFit.cover,
        alignment: alignment,
        child: SizedBox(
          width: destination.width,
          height: destination.height,
          child: poster ?? source!,
        ),
      );
    }

    final insets = widget.originClipFractions;
    final hasClip = insets != EdgeInsets.zero;

    Widget renderedSource;
    if (hasClip && shapeE < 0.999) {
      // The edge card on the rail has unclipped dimensions larger than the visible frame.
      // Position the source artwork with the exact offset so inside the clipped flyer
      // it reveals the exact same slice of the still that was visible on the rail!
      final fullW = (1.0 - insets.left - insets.right) > 0.001
          ? frame.width / (1.0 - insets.left - insets.right)
          : frame.width;
      final fullH = (1.0 - insets.top - insets.bottom) > 0.001
          ? frame.height / (1.0 - insets.top - insets.bottom)
          : frame.height;
      final currentW = ui.lerpDouble(fullW, frame.width, shapeE)!;
      final currentH = ui.lerpDouble(fullH, frame.height, shapeE)!;
      final currentLeft = ui.lerpDouble(-fullW * insets.left, 0.0, shapeE)!;
      final currentTop = ui.lerpDouble(-fullH * insets.top, 0.0, shapeE)!;

      renderedSource = Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: currentLeft,
            top: currentTop,
            width: currentW,
            height: currentH,
            child: source,
          ),
        ],
      );
    } else {
      renderedSource = source;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fills the frame: matches the pressed card exactly at the start.
        Opacity(opacity: (1 - blend).clamp(0.0, 1.0), child: renderedSource),
        Opacity(
          opacity: blend.clamp(0.0, 1.0),
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: alignment,
            child: SizedBox(
              width: destination.width,
              height: destination.height,
              child: poster,
            ),
          ),
        ),
      ],
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
