import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_spring.dart';
import 'package:flutter/material.dart';

/// A cascading layered card/sheet component inspired by Apple VisionOS and macOS.
///
/// When nested or stacked (indicated by [depth] > 0), the underlying sheet
/// recedes backwards along the Z-axis, shrinks slightly, shifts upward,
/// and applies a subtle dimming barrier to create authentic physical depth.
class PeekCascadingSheet extends StatelessWidget {
  const PeekCascadingSheet({
    super.key,
    required this.child,
    this.depth = 0,
    this.duration = const Duration(milliseconds: 280),
    this.curve = PeekCurves.spatialEnter,
  });

  final Widget child;

  /// Stacking depth index (0 = active foreground, 1 = first background layer, etc.)
  final int depth;

  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isTest) return child;

    final targetScale = (1.0 - (depth * 0.045)).clamp(0.85, 1.0);
    final targetOffsetY = -14.0 * depth;
    final dimAlpha = (depth * 0.30).clamp(0.0, 0.70);

    return AnimatedSlide(
      offset: Offset(0, targetOffsetY / 200.0),
      duration: duration,
      curve: curve,
      child: AnimatedScale(
        scale: targetScale,
        alignment: Alignment.topCenter,
        duration: duration,
        curve: curve,
        child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          if (depth > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: dimAlpha > 0.001 ? 1.0 : 0.0,
                  duration: duration,
                  curve: curve,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: dimAlpha),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
}

/// A multi-step cascading card stack that allows forward navigation into sub-panels
/// while retaining the previous panel in receding physical depth.
class PeekCascadingStack extends StatefulWidget {
  const PeekCascadingStack({
    super.key,
    required this.pages,
    this.currentIndex = 0,
    this.onPop,
  });

  final List<Widget> pages;
  final int currentIndex;
  final VoidCallback? onPop;

  @override
  State<PeekCascadingStack> createState() => _PeekCascadingStackState();
}

class _PeekCascadingStackState extends State<PeekCascadingStack> {
  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    if (AppMotion.isTest) {
      return widget.pages[widget.currentIndex.clamp(0, widget.pages.length - 1)];
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        for (var i = 0; i <= widget.currentIndex && i < widget.pages.length; i++)
          PeekCascadingSheet(
            depth: widget.currentIndex - i,
            child: widget.pages[i],
          ),
      ],
    );
  }
}

/// Signature modal bottom sheet presentation route with spatial physics,
/// glass barrier dim, and secondary route recess.
class PeekCascadingSheetRoute<T> extends PopupRoute<T> {
  PeekCascadingSheetRoute({
    required this.builder,
    super.settings,
    this.barrierDismissible = true,
    this.barrierColor = const Color(0x99000000),
    this.barrierLabel,
    this.transitionDuration = const Duration(milliseconds: 320),
    this.reverseTransitionDuration = const Duration(milliseconds: 240),
  });

  final WidgetBuilder builder;

  @override
  final bool barrierDismissible;

  @override
  final Color barrierColor;

  @override
  final String? barrierLabel;

  @override
  final Duration transitionDuration;

  @override
  final Duration reverseTransitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
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
        begin: const Offset(0, 0.08),
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
  }
}
