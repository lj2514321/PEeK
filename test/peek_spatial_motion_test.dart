import 'package:embyplayer/src/core/presentation/peek_border_beam.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Peek Next-Gen Motion System', () {
    testWidgets('PeekBorderBeam renders child cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PeekBorderBeam(
                child: const SizedBox(
                  width: 100,
                  height: 40,
                  child: Text('BorderBeamTest'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('BorderBeamTest'), findsOneWidget);
    });

    test('PeekCurves and PeekSprings have valid physical parameters', () {
      expect(PeekCurves.spatialEnter, isNotNull);
      expect(PeekCurves.depthRecess, isNotNull);
      expect(PeekCurves.jellyStretch, isNotNull);
      expect(PeekCurves.springSnap, isNotNull);
      expect(PeekCurves.cinemaFade, isNotNull);

      expect(PeekSprings.gentle.stiffness, 180.0);
      expect(PeekSprings.snappy.stiffness, 260.0);
      expect(PeekSprings.jelly.stiffness, 220.0);
      expect(PeekSprings.stiff.stiffness, 340.0);
    });

    testWidgets(
      'PeekSpatialPageRoute and TheatricalIrisPageRoute create valid routes',
      (tester) async {
        final spatialRoute = PeekSpatialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('SpatialPage')),
        );
        final irisRoute = TheatricalIrisPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('CinemaPage')),
        );

        expect(
          spatialRoute.transitionDuration,
          const Duration(milliseconds: 420),
        );
        expect(
          spatialRoute.reverseTransitionDuration,
          const Duration(milliseconds: 300),
        );
        expect(irisRoute.transitionDuration, const Duration(milliseconds: 380));
        expect(
          irisRoute.reverseTransitionDuration,
          const Duration(milliseconds: 280),
        );
      },
    );

    testWidgets('PeekSpringValueBuilder updates smoothly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PeekSpringValueBuilder(
              value: 42.0,
              builder: (context, val) => Text('Val: $val'),
            ),
          ),
        ),
      );

      expect(find.text('Val: 42.0'), findsOneWidget);
    });

    testWidgets(
      'PeekMagneticButton renders child and handles interactions safely',
      (tester) async {
        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: PeekMagneticButton(
                  onTap: () => tapped = true,
                  child: const Text('MagneticBtn'),
                ),
              ),
            ),
          ),
        );

        expect(find.text('MagneticBtn'), findsOneWidget);
        await tester.tap(find.text('MagneticBtn'));
        expect(tapped, isTrue);
      },
    );

    testWidgets(
      'PeekCascadingSheet and Stack render content at various depths',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  PeekCascadingSheet(depth: 0, child: Text('ForegroundSheet')),
                  PeekCascadingSheet(depth: 1, child: Text('RecedingSheet')),
                ],
              ),
            ),
          ),
        );

        expect(find.text('ForegroundSheet'), findsOneWidget);
        expect(find.text('RecedingSheet'), findsOneWidget);
      },
    );

    test('PeekCascadingSheetRoute creates valid cascading route', () {
      final route = PeekCascadingSheetRoute<void>(
        builder: (_) => const Scaffold(body: Text('CascadingRoute')),
      );

      expect(route.transitionDuration, const Duration(milliseconds: 320));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 240),
      );
      expect(route.barrierDismissible, isTrue);
      expect(route.barrierColor, const Color(0x99000000));
    });
  });
}
