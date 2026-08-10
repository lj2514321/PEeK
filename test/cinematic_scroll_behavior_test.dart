import 'package:embyplayer/src/core/presentation/cinematic_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CinematicScrollBehavior returns CinematicScrollPhysics and enables drag devices', (tester) async {
    const behavior = CinematicScrollBehavior();

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          final physics = behavior.getScrollPhysics(context);
          expect(physics, isA<CinematicScrollPhysics>());
          expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
          return const SizedBox();
        },
      ),
    );
  });
}
