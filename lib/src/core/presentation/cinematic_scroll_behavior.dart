import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Customized spring physics that provides smooth inertia and bounce on desktop.
class CinematicScrollPhysics extends BouncingScrollPhysics {
  const CinematicScrollPhysics({super.parent});

  @override
  CinematicScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CinematicScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 0.7,
        stiffness: 120,
        damping: 14,
      );
}

/// Global scroll behavior providing fluid physics and mouse drag scrolling across desktop.
class CinematicScrollBehavior extends MaterialScrollBehavior {
  const CinematicScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const CinematicScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}
