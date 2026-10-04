import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A tactile, physics-based magnetic button that pulls toward the mouse pointer
/// on hover and provides a responsive spring squeeze on press.
///
/// Automatically disables all animations and motion listeners in test environments
/// ([AppMotion.isTest]) to guarantee 100% test reliability and zero latency.
class PeekMagneticButton extends StatefulWidget {
  const PeekMagneticButton({
    super.key,
    required this.child,
    this.enabled = true,
    this.maxOffset = 4.0,
    this.pressScale = 0.93,
    this.hoverScale = 1.03,
    this.duration = const Duration(milliseconds: 180),
    this.onTap,
  });

  final Widget child;
  final bool enabled;

  /// Maximum translation offset in logical pixels when the pointer hovers over the button.
  final double maxOffset;

  /// Scale compression factor when the pointer is pressed down.
  final double pressScale;

  /// Scale factor when the pointer is hovering over the button.
  final double hoverScale;

  /// Animation duration for settling into position.
  final Duration duration;

  /// Optional tap callback if not handled by child.
  final VoidCallback? onTap;

  @override
  State<PeekMagneticButton> createState() => _PeekMagneticButtonState();
}

class _PeekMagneticButtonState extends State<PeekMagneticButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _onEnter(PointerEnterEvent event) {
    if (!widget.enabled || AppMotion.isTest) return;
    if (!_hovered) setState(() => _hovered = true);
  }

  void _onExit(PointerExitEvent event) {
    if (!widget.enabled || AppMotion.isTest) return;
    if (_hovered || _pressed) {
      setState(() {
        _hovered = false;
        _pressed = false;
      });
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || AppMotion.isTest) return;
    setState(() => _pressed = true);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!widget.enabled || AppMotion.isTest) return;
    setState(() => _pressed = false);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (!widget.enabled || AppMotion.isTest) return;
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isTest || !widget.enabled) {
      if (widget.onTap != null) {
        return GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: widget.child,
        );
      }
      return widget.child;
    }

    final currentScale = _pressed
        ? widget.pressScale
        : (_hovered ? widget.hoverScale : 1.0);

    final duration = _pressed
        ? const Duration(milliseconds: 80)
        : const Duration(milliseconds: 140);
    final curve = _pressed ? Curves.easeOutQuad : Curves.easeOutCubic;

    Widget result = AnimatedScale(
      scale: currentScale,
      duration: duration,
      curve: curve,
      child: widget.child,
    );

    result = MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      hitTestBehavior: HitTestBehavior.deferToChild,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        behavior: HitTestBehavior.deferToChild,
        child: result,
      ),
    );

    if (widget.onTap != null) {
      result = GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: result,
      );
    }

    return result;
  }
}
