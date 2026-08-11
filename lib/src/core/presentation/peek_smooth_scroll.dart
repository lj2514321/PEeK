import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Intercepts discrete mouse wheel scroll events and smoothly interpolates
/// the target scroll position with frequency-based momentum acceleration and
/// high-fps responsive easing curves.
class PeekSmoothScroll extends StatefulWidget {
  const PeekSmoothScroll({
    super.key,
    required this.child,
    this.controller,
    this.scrollSpeedMultiplier = 1.4,
  });

  final Widget child;
  final ScrollController? controller;
  final double scrollSpeedMultiplier;

  @override
  State<PeekSmoothScroll> createState() => _PeekSmoothScrollState();
}

class _PeekSmoothScrollState extends State<PeekSmoothScroll> {
  DateTime? _lastScrollTime;
  double _velocityMultiplier = 1.0;
  double? _targetOffset;

  void _handlePointerSignal(PointerSignalEvent event, BuildContext context) {
    if (event is! PointerScrollEvent) return;

    final controller = widget.controller ??
        PrimaryScrollController.maybeOf(context);

    if (controller == null || !controller.hasClients) return;

    final position = controller.position;
    final now = DateTime.now();

    // Calculate Acceleration Multiplier based on scroll tick frequency
    if (_lastScrollTime != null) {
      final interval = now.difference(_lastScrollTime!).inMilliseconds;
      if (interval < 140) {
        // Rapid scrolling -> accumulate velocity acceleration
        _velocityMultiplier = (_velocityMultiplier + 0.45).clamp(1.0, 4.0);
      } else if (interval > 280) {
        // Slowed down -> reset velocity multiplier
        _velocityMultiplier = 1.0;
      }
    }
    _lastScrollTime = now;

    final delta = event.scrollDelta.dy *
        widget.scrollSpeedMultiplier *
        _velocityMultiplier;

    if (delta == 0) return;

    final currentTarget = _targetOffset ?? position.pixels;

    final newTarget = (currentTarget + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    _targetOffset = newTarget;

    // Dynamic responsive duration based on distance
    final distance = (newTarget - position.pixels).abs();
    final durationMs = (160 + (distance * 0.12)).clamp(130.0, 260.0).toInt();

    controller
        .animateTo(
          newTarget,
          duration: Duration(milliseconds: durationMs),
          curve: const Cubic(0.15, 0.85, 0.25, 1.0),
        )
        .whenComplete(() {
      if (_targetOffset == newTarget) {
        _targetOffset = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) => _handlePointerSignal(event, context),
      child: widget.child,
    );
  }
}
