import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PeekSmoothScroll renders child without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PeekSmoothScroll(child: Text('Smooth Scroll Child')),
        ),
      ),
    );

    expect(find.text('Smooth Scroll Child'), findsOneWidget);
  });

  testWidgets(
    'PeekSmoothScroll automatically provides SmoothScrollController to descendant ScrollView on desktop',
    (tester) async {
      late BuildContext innerContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PeekSmoothScroll(
              child: Builder(
                builder: (context) {
                  innerContext = context;
                  return ListView(
                    children: List.generate(
                      50,
                      (i) => SizedBox(height: 50, child: Text('Item $i')),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final primary = PrimaryScrollController.maybeOf(innerContext);
      expect(primary, isNotNull);
      expect(primary, isA<SmoothScrollController>());

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position, isA<SmoothScrollPosition>());
    },
  );

  testWidgets('SmoothScrollPosition handles momentum and direction reversal', (
    tester,
  ) async {
    final controller = SmoothScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PeekSmoothScroll(
            controller: controller,
            child: ListView(
              controller: controller,
              children: List.generate(
                100,
                (i) => SizedBox(height: 50, child: Text('Item $i')),
              ),
            ),
          ),
        ),
      ),
    );

    expect(controller.hasClients, isTrue);
    final position = controller.position as SmoothScrollPosition;
    expect(position.pixels, 0.0);

    // Initial forward scroll
    position.pointerScroll(100.0);
    expect(position.pixels, 0.0); // Animate started, not instant jump!

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(position.pixels, greaterThan(0.0));

    // Rapid reverse scroll: should instantly reverse target without getting stuck
    position.pointerScroll(-120.0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Settle back to start
    expect(position.pixels, 0.0);

    controller.dispose();
  });
}
