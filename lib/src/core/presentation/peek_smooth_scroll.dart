import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A [ScrollPositionWithSingleContext] that replaces Flutter's instant
/// [pointerScroll] jump with a velocity-continuous spring.
///
/// Why not a tween: the previous implementation called `animateTo` for every
/// wheel packet. Each call begins a fresh `DrivenScrollActivity`, whose
/// `AnimationController` reports t=0 on its first tick, so the frame in which a
/// packet landed never moved. With packets arriving every other frame half of
/// all frames were dead, and with a packet per frame the scroll froze solid.
///
/// This version keeps the motion state (offset + velocity) inside a single
/// [_SpringScrollActivity]. A new packet only moves the target; the spring
/// keeps its velocity, so every frame produces motion and retargeting is
/// continuous instead of restarting.
class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    this.scrollSpeedMultiplier = 1.6,
  });

  /// Multiplies the raw wheel delta before it is added to the spring target.
  ///
  /// This is the single knob for scroll speed. The old implementation also had
  /// an interaction-rate multiplier (up to 4.5x) to compensate for the dead
  /// frames it lost; with a spring the motion is continuous, so that multiplier
  /// would simply run away (~7x at a sustained spin). Fine-grained packets
  /// (precision trackpads) stay 1:1.
  final double scrollSpeedMultiplier;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) return;

    final double minExtent = minScrollExtent;
    final double maxExtent = maxScrollExtent;
    if (maxExtent <= minExtent) return;

    final double scale = delta.abs() < 12.0 ? 1.0 : scrollSpeedMultiplier;
    final double scaled = delta * scale;

    final ScrollActivity? current = activity;
    if (current is _SpringScrollActivity) {
      // Retarget the running spring. Velocity is deliberately preserved: this
      // is what keeps the motion continuous while packets keep arriving.
      current.extend(scaled);
      return;
    }

    final double target = (pixels + scaled).clamp(minExtent, maxExtent);
    if ((pixels - target).abs() <= physics.toleranceFor(this).distance) return;

    beginActivity(_SpringScrollActivity(position: this, target: target));
  }
}

/// Drives a [SmoothScrollPosition] towards a target offset with a critically
/// damped spring, integrating on every frame so motion never stalls between
/// wheel packets.
class _SpringScrollActivity extends ScrollActivity {
  _SpringScrollActivity({
    required SmoothScrollPosition position,
    required double target,
  }) : _position = position,
       _x = position.pixels,
       _velocity = 0.0,
       super(position) {
    _target = target;
    _ticker = position.context.vsync.createTicker(_tick);
    _ticker.start();
  }

  /// Spring stiffness (omega^2) and damping (2 * omega): critically damped, so
  /// a notch glides to its target in ~150ms without overshooting, and a
  /// reversal (spin the wheel the other way) settles in ~200ms.
  static const double _omega = 32.0;
  static const double _stiffness = _omega * _omega;
  static const double _damping = 2 * _omega;

  /// Integration step. Fixed and small enough for the spring to stay stable
  /// even when a single frame is long (first frame after a stall, or a widget
  /// test pumping several hundred milliseconds at once).
  static const double _substep = 1 / 240;

  /// Below this residual offset the spring snaps onto the target and goes
  /// idle, so scroll offsets land on exact values instead of creeping.
  static const double _settleDistance = 1.0;

  /// ~0.4px per frame at 60Hz: slow enough that snapping the last pixel is
  /// invisible, fast enough that a reversal lands instead of creeping.
  static const double _settleVelocity = 24.0;

  /// A ticker reports elapsed == 0 on its very first tick, so integrating by
  /// delta would drop the first frame of every burst. Treat the first tick as
  /// one nominal frame instead.
  static const double _nominalFrame = 1 / 60;

  final SmoothScrollPosition _position;
  late final Ticker _ticker;

  Duration? _lastElapsed;
  double _x;
  late double _target;
  double _velocity;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _velocity;

  @override
  bool get shouldIgnorePointer => false;

  /// Extends the current target by [delta] without disturbing the velocity.
  void extend(double delta) {
    _target = (_target + delta).clamp(
      _position.minScrollExtent,
      _position.maxScrollExtent,
    );
  }

  @override
  void dispose() {
    if (_ticker.isActive) _ticker.stop(canceled: true);
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final Duration? last = _lastElapsed;
    _lastElapsed = elapsed;

    final double dt = last == null
        ? _nominalFrame
        : (elapsed - last).inMicroseconds / Duration.microsecondsPerSecond;
    if (dt <= 0) return;

    final double minExtent = _position.minScrollExtent;
    final double maxExtent = _position.maxScrollExtent;
    _target = _target.clamp(minExtent, maxExtent);

    var remaining = math.min(dt, 0.5);

    while (remaining > 0) {
      final double step = math.min(remaining, _substep);
      remaining -= step;

      final double acceleration =
          _stiffness * (_target - _x) - _damping * _velocity;
      _velocity += acceleration * step;
      _x += _velocity * step;

      if (_x <= minExtent) {
        _x = minExtent;
        if (_velocity < 0) _velocity = 0;
      } else if (_x >= maxExtent) {
        _x = maxExtent;
        if (_velocity > 0) _velocity = 0;
      }

      if ((_target - _x).abs() <= _settleDistance &&
          _velocity.abs() <= _settleVelocity) {
        _finish();
        return;
      }
    }

    _position.setPixels(_x);
    // `setPixels` runs the scroll physics boundary conditions; resync so the
    // next substep starts from the offset that was actually committed.
    _x = _position.pixels;
  }

  void _finish() {
    if (_ticker.isActive) _ticker.stop(canceled: true);
    // Land exactly on the target: tests and resume logic compare offsets.
    _position.setPixels(_target);
    _position.goIdle();
  }
}

/// A [ScrollController] that creates [SmoothScrollPosition] to replace native
/// instant wheel jumps with a momentum-preserving spring.
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
/// inherits a [SmoothScrollController] on desktop platforms (including
/// Windows), enforcing momentum-preserving wheel scrolling globally.
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
