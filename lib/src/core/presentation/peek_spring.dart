import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/material.dart';

/// Predefined physical spring configurations for tactile, grounded desktop motion.
class PeekSprings {
  const PeekSprings._();

  /// Soft, buttery spatial spring for route page pushes and large surface morphing.
  static const SpringDescription gentle = SpringDescription(
    mass: 1.0,
    stiffness: 180.0,
    damping: 22.0,
  );

  /// Snappy tactile spring for buttons, capsules, and interactive pills.
  static const SpringDescription snappy = SpringDescription(
    mass: 1.0,
    stiffness: 260.0,
    damping: 24.0,
  );

  /// Elastic jelly spring with slight overshoot for tab indicators and floating badges.
  static const SpringDescription jelly = SpringDescription(
    mass: 1.0,
    stiffness: 220.0,
    damping: 17.0,
  );

  /// Stiff responsive spring for pointer following and 3D card tilt.
  static const SpringDescription stiff = SpringDescription(
    mass: 1.0,
    stiffness: 340.0,
    damping: 30.0,
  );
}

/// Signature high-end cubic bezier curves tailored for spatial depth and jelly inertia.
class PeekCurves {
  const PeekCurves._();

  /// Spatial drop-in curve with balanced acceleration and silky deceleration.
  static const Curve spatialEnter = Cubic(0.22, 0.84, 0.26, 1.0);

  /// Depth recess curve for background elements retreating along Z-axis.
  static const Curve depthRecess = Cubic(0.24, 0.08, 0.22, 1.0);

  /// Fluid elongation curve for jelly squash & stretch acceleration.
  static const Curve jellyStretch = Cubic(0.20, 0.88, 0.28, 1.0);

  /// Micro-overshoot spring bounce for settling into place.
  static const Curve springSnap = Cubic(0.34, 1.38, 0.64, 1.0);

  /// Silky smooth cinema dissolve curve.
  static const Curve cinemaFade = Cubic(0.22, 0.80, 0.26, 1.0);
}

/// A smooth physics-inspired spring animated builder for a target double value.
/// Automatically degrades to an instant update when running tests or when reduced motion is preferred.
class PeekSpringValueBuilder extends StatefulWidget {
  const PeekSpringValueBuilder({
    super.key,
    required this.value,
    required this.builder,
    this.spring = PeekSprings.snappy,
    this.curve = PeekCurves.spatialEnter,
    this.duration = const Duration(milliseconds: 280),
  });

  final double value;
  final Widget Function(BuildContext context, double animatedValue) builder;
  final SpringDescription spring;
  final Curve curve;
  final Duration duration;

  @override
  State<PeekSpringValueBuilder> createState() => _PeekSpringValueBuilderState();
}

class _PeekSpringValueBuilderState extends State<PeekSpringValueBuilder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late double _from;
  late double _target;

  @override
  void initState() {
    super.initState();
    _from = widget.value;
    _target = widget.value;
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(PeekSpringValueBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (AppMotion.isTest) {
        _from = widget.value;
        _target = widget.value;
        return;
      }
      _from = _currentValue;
      _target = widget.value;
      _controller.duration = widget.duration;
      _controller.forward(from: 0.0);
    }
  }

  double get _currentValue {
    if (AppMotion.isTest) return widget.value;
    final curved = widget.curve.transform(_controller.value);
    return _from + ((_target - _from) * curved);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _currentValue);
  }
}
