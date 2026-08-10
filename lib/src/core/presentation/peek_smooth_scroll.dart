import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Intercepts discrete mouse wheel scroll events and smoothly interpolates
/// the target scroll position with easeOutCubic animation.
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
  double? _targetOffset;

  void _handlePointerSignal(PointerSignalEvent event, BuildContext context) {
    if (event is! PointerScrollEvent) return;

    final controller = widget.controller ??
        PrimaryScrollController.maybeOf(context);

    if (controller == null || !controller.hasClients) return;

    final position = controller.position;
    final delta = event.scrollDelta.dy * widget.scrollSpeedMultiplier;

    if (delta == 0) return;

    final currentTarget = _targetOffset ?? position.pixels;

    final newTarget = (currentTarget + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    _targetOffset = newTarget;

    controller
        .animateTo(
          newTarget,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
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
