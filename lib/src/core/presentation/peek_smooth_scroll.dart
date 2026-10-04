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

    // Reversal detection: if current target is ahead in one direction and new delta
    // goes in the opposite direction, immediately anchor back to physical pixels
    // and reset acceleration to provide immediate, lag-free responsiveness.
    if (_targetOffset != null) {
      final heading = _targetOffset! - pixels;
      if ((heading > 0 && delta < 0) || (heading < 0 && delta > 0)) {
        _targetOffset = pixels;
        _velocityMultiplier = 1.0;
      }
    }

    // Momentum Acceleration Multiplier
    if (_lastScrollTime != null) {
      final interval = now.difference(_lastScrollTime!).inMilliseconds;
      if (interval < 140) {
        _velocityMultiplier = (_velocityMultiplier + 0.55).clamp(1.0, 4.5);
      } else if (interval > 260) {
        _velocityMultiplier = 1.0;
      } else {
        // Smooth linear decay between 140ms and 260ms
        final factor = (260 - interval) / 120.0;
        _velocityMultiplier =
            (1.0 + (_velocityMultiplier - 1.0) * factor).clamp(1.0, 4.5);
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

/// Scope wrapper widget that ensures any unparented [ScrollView],
/// [SingleChildScrollView], or [ListView] within its subtree automatically
/// inherits a [SmoothScrollController] on desktop platforms (including Windows),
/// enforcing buttery smooth momentum scrolling globally.
class PeekSmoothScroll extends StatefulWidget {
  const PeekSmoothScroll({
    super.key,
    required this.child,
    this.controller,
    this.scrollSpeedMultiplier = 1.6,
    this.scrollDirection = Axis.vertical,
  });

  final Widget child;
  final ScrollController? controller;
  final double scrollSpeedMultiplier;
  final Axis scrollDirection;

  @override
  State<PeekSmoothScroll> createState() => _PeekSmoothScrollState();
}

class _PeekSmoothScrollState extends State<PeekSmoothScroll> {
  ScrollController? _internalController;

  ScrollController get _effectiveController =>
      widget.controller ??
      (_internalController ??= SmoothScrollController(
        scrollSpeedMultiplier: widget.scrollSpeedMultiplier,
      ));

  @override
  void didUpdateWidget(covariant PeekSmoothScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && _internalController != null) {
      _internalController!.dispose();
      _internalController = null;
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: _effectiveController,
      scrollDirection: widget.scrollDirection,
      automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
      child: widget.child,
    );
  }
}
