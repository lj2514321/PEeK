import 'package:embyplayer/src/core/presentation/peek_horizontal_rail.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Edge Card Proportion Retract & Early-Stage Shape Adaptation Tests', () {
    testWidgets('recordTap detects edge clipping in PeekHorizontalRail', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: PeekHorizontalRail(
                railId: 'test-rail',
                semanticLabel: 'Test',
                height: 250,
                itemCount: 10,
                itemExtent: 220,
                spacing: 14,
                itemBuilder: (context, index) {
                  return Builder(
                    key: ValueKey('item-$index'),
                    builder: (ctx) {
                      return Listener(
                        onPointerDown: (e) {
                          PeekMotionOrigin.recordTap(ctx, e.position);
                        },
                        child: Container(
                          color: Colors.blue,
                          child: Center(child: Text('Item $index')),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap item 0 (fully visible at 0..220)
      await tester.tap(find.byKey(const ValueKey('item-0')));
      await tester.pump();
      expect(PeekMotionOrigin.lastTapClipFractions, equals(EdgeInsets.zero));

      // Tap item 2 (at 468..688, partially visible in 500px container)
      await tester.tapAt(const Offset(480, 100));
      await tester.pump();

      expect(PeekMotionOrigin.lastTapRect, isNotNull);
      final clip = PeekMotionOrigin.lastTapClipFractions;
      expect(clip.left, equals(0.0));
      expect(clip.top, equals(0.0));
      expect(clip.bottom, equals(0.0));
      expect(clip.right, greaterThan(0.8));
      expect(clip.right, lessThan(0.9));
    });

    testWidgets(
      'PeekAnchorMorphTransition completes shape deformation early in retract (not at late stage)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        late AnimationController controller;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (ctx) {
                    controller = AnimationController(
                      vsync: Navigator.of(ctx),
                      duration: const Duration(milliseconds: 300),
                    );
                    return PeekAnchorMorphTransition(
                      animation: controller,
                      secondaryAnimation: kAlwaysDismissedAnimation,
                      originRect: const Rect.fromLTWH(
                        800,
                        300,
                        200,
                        300,
                      ), // Full unclipped: 200x300
                      originClipFractions: const EdgeInsets.only(
                        right: 0.25,
                      ), // 25% clipped: visible 150x300, ratio 0.50
                      destination: (size) => const Rect.fromLTWH(
                        50,
                        100,
                        200,
                        300,
                      ), // Destination: 200x300, ratio 0.6667
                      poster: Container(color: Colors.purple),
                      child: const Scaffold(body: Text('Detail Page Content')),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // Start at settled detail page (value 1.0)
        controller.value = 1.0;
        await tester.pump();

        // Begin retract: p = 1.0 - value
        controller.reverse(from: 1.0);
        await tester.pump();

        // Advance to p = 0.50 (value = 0.50, past early cutoff 0.35)
        controller.value = 0.50;
        await tester.pump();

        final boxFinder = find.byKey(const Key('flying-poster-box'));
        expect(boxFinder, findsOneWidget);
        final Positioned posMid = tester.widget(boxFinder);

        // At p = 0.50, shape deformation is ALREADY finished early:
        // Aspect ratio must already match origin visible ratio: 150 / 300 = 0.50
        final midAspect = posMid.width! / posMid.height!;
        expect(midAspect, closeTo(0.50, 0.01));

        // Advance to late stage: p = 0.85 (value = 0.15)
        controller.value = 0.15;
        await tester.pump();
        final Positioned posLate = tester.widget(boxFinder);
        final lateAspect = posLate.width! / posLate.height!;

        // In the late stage, aspect ratio DOES NOT change — it remains 0.50!
        expect(lateAspect, closeTo(0.50, 0.01));

        // Advance to the end of retract (landing back on card)
        controller.value = 0.0;
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'PeekAnchorMorphTransition completes cross-fade (渐变) during morph before animation ends',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        late AnimationController controller;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (ctx) {
                    controller = AnimationController(
                      vsync: Navigator.of(ctx),
                      duration: const Duration(milliseconds: 300),
                    );
                    return PeekAnchorMorphTransition(
                      animation: controller,
                      secondaryAnimation: kAlwaysDismissedAnimation,
                      originRect: const Rect.fromLTWH(800, 300, 200, 300),
                      originClipFractions: const EdgeInsets.only(right: 0.25),
                      originCardToken: 'edge-card-token',
                      destination: (size) =>
                          const Rect.fromLTWH(50, 100, 200, 300),
                      poster: Container(color: Colors.purple),
                      child: const Scaffold(body: Text('Detail Page Content')),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // Settle at detail page
        controller.value = 1.0;
        await tester.pump();

        // Begin retract
        controller.reverse(from: 1.0);
        await tester.pump();

        // At raw = 0.50 (during flight): card opacity is 0.0 (hidden), flyer is active
        controller.value = 0.50;
        await tester.pump();
        expect(PeekSharedFlight.cardFlightOpacity.value, closeTo(0.0, 0.01));
        expect(find.byKey(const Key('flying-poster-box')), findsOneWidget);

        // At raw = 0.11 (mid-crossfade): card is smoothly fading in, flyer is active
        controller.value = 0.11;
        await tester.pump();
        expect(PeekSharedFlight.cardFlightOpacity.value, greaterThan(0.40));
        expect(PeekSharedFlight.cardFlightOpacity.value, lessThan(0.65));
        expect(find.byKey(const Key('flying-poster-box')), findsOneWidget);

        // At raw = 0.02 (before animation ends): card is ALREADY 100% visible, flyer has completed hand-off
        controller.value = 0.02;
        await tester.pump();
        expect(PeekSharedFlight.cardFlightOpacity.value, closeTo(1.0, 0.01));
        // Flyer has completed hand-off
        expect(find.byKey(const Key('flying-poster-box')), findsNothing);

        // At raw = 0.00 (animation terminates): card remains 100% visible with zero sudden pop/jump
        controller.value = 0.0;
        await tester.pumpAndSettle();
        expect(PeekSharedFlight.cardFlightOpacity.value, equals(1.0));
        expect(PeekSharedFlight.activeCardToken.value, isNull);
      },
    );

    testWidgets(
      'Continue Watching landscape edge card cross-fade completes mid-flight during morph with edge crop alignment',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        late AnimationController controller;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (ctx) {
                    controller = AnimationController(
                      vsync: Navigator.of(ctx),
                      duration: const Duration(milliseconds: 300),
                    );
                    return PeekAnchorMorphTransition(
                      animation: controller,
                      secondaryAnimation: kAlwaysDismissedAnimation,
                      originRect: const Rect.fromLTWH(800, 300, 280, 160), // Wide 16:9 still
                      originClipFractions: const EdgeInsets.only(right: 0.30), // 30% clipped on right
                      originCardToken: 'cw-edge-token',
                      destination: (size) => const Rect.fromLTWH(50, 100, 200, 300), // 2:3 portrait
                      poster: Container(key: const ValueKey('dest-poster'), color: Colors.blue),
                      source: Container(key: const ValueKey('source-still'), color: Colors.amber),
                      child: const Scaffold(body: Text('CW Detail Page')),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // Settle at detail page (forward finished)
        controller.value = 1.0;
        await tester.pump();

        // Begin retract (pop back towards Continue Watching rail)
        controller.reverse(from: 1.0);
        controller.value = 0.85;
        await tester.pump();

        // Flyer is active in the air
        final flyerFinder = find.byKey(const Key('flying-poster-box'));
        expect(flyerFinder, findsOneWidget);

        // At raw = 0.50 (in the middle of morph):
        // Both source still and destination poster are present and smoothly cross-fading
        controller.value = 0.50;
        await tester.pump();
        expect(find.byKey(const ValueKey('dest-poster')), findsOneWidget);
        expect(find.byKey(const ValueKey('source-still')), findsOneWidget);

        // At raw = 0.25 (cross-fade has ALREADY completed during morphing flight):
        // Source still is aligned to edge crop without sudden late pop
        controller.value = 0.25;
        await tester.pump();
        expect(flyerFinder, findsOneWidget);
        expect(find.byKey(const ValueKey('source-still')), findsOneWidget);

        // Land cleanly at raw = 0.0
        controller.value = 0.0;
        await tester.pumpAndSettle();
        expect(PeekSharedFlight.cardFlightOpacity.value, equals(1.0));
      },
    );
  });
}
