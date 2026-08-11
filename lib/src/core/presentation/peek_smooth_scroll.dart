import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Intercepts discrete mouse wheel scroll events and resolves them via
/// GestureBinding's PointerSignalResolver to prevent native instant jumpTo,
/// providing fluid momentum acceleration and buttery smooth easing.
class PeekSmoothScroll extends StatefulWidget {
  const PeekSmoothScroll({
    super.key,
    required this.child,
    this.controller,
    this.scrollSpeedMultiplier = 1.6,
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

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;

    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (resolvedEvent) => _handleResolvedScroll(resolvedEvent as PointerScrollEvent),
    );
  }

  void _handleResolvedScroll(PointerScrollEvent event) {
    final controller = widget.controller ??
        PrimaryScrollController.maybeOf(context);

    if (controller == null || !controller.hasClients) return;

    final position = controller.position;
    final now = DateTime.now();

    if (_lastScrollTime != null) {
      final interval = now.difference(_lastScrollTime!).inMilliseconds;
      if (interval < 140) {
        _velocityMultiplier = (_velocityMultiplier + 0.55).clamp(1.0, 4.5);
      } else if (interval > 260) {
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

    final distance = (newTarget - position.pixels).abs();
    final durationMs = (160 + (distance * 0.12)).clamp(140.0, 280.0).toInt();

    controller
        .animateTo(
          newTarget,
          duration: Duration(milliseconds: durationMs),
          curve: const Cubic(0.12, 0.88, 0.22, 1.0),
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
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }
}
