import 'package:flutter/material.dart';

/// A custom [ScrollPositionWithSingleContext] that overrides Flutter's default
/// instant [pointerScroll] jumpTo behavior with momentum acceleration and fluid
/// cubic easing.
class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    this.scrollSpeedMultiplier = 1.6,
  });

  final double scrollSpeedMultiplier;
  DateTime? _lastScrollTime;
  double _velocityMultiplier = 1.0;
  double? _targetOffset;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) return;

    final now = DateTime.now();

    // Momentum Acceleration Multiplier
    if (_lastScrollTime != null) {
      final interval = now.difference(_lastScrollTime!).inMilliseconds;
      if (interval < 140) {
        _velocityMultiplier = (_velocityMultiplier + 0.55).clamp(1.0, 4.5);
      } else if (interval > 260) {
        _velocityMultiplier = 1.0;
      }
    }
    _lastScrollTime = now;

    final scaledDelta = delta * scrollSpeedMultiplier * _velocityMultiplier;
    final currentTarget = _targetOffset ?? pixels;
    final newTarget = (currentTarget + scaledDelta).clamp(
      minScrollExtent,
      maxScrollExtent,
    );

    _targetOffset = newTarget;

    final distance = (newTarget - pixels).abs();
    final durationMs = (160 + (distance * 0.12)).clamp(140.0, 280.0).toInt();

    animateTo(
      newTarget,
      duration: Duration(milliseconds: durationMs),
      curve: const Cubic(0.12, 0.88, 0.22, 1.0),
    ).whenComplete(() {
      if (_targetOffset == newTarget) {
        _targetOffset = null;
      }
    });
  }
}

/// A [ScrollController] that creates [SmoothScrollPosition] to directly disable
/// native instant wheel jumpTo and enforce smooth momentum scrolling.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.scrollSpeedMultiplier = 1.6,
  });

  final double scrollSpeedMultiplier;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return SmoothScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      scrollSpeedMultiplier: scrollSpeedMultiplier,
    );
  }
}

/// Helper wrapper widget to pass children cleanly if needed.
class PeekSmoothScroll extends StatelessWidget {
  const PeekSmoothScroll({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
