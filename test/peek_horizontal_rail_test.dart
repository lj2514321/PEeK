import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_horizontal_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows desktop controls only when the rail can move', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_railApp());
    await tester.pumpAndSettle();

    final previous = find.byKey(const ValueKey('test-rail-previous'));
    final next = find.byKey(const ValueKey('test-rail-next'));
    expect(previous, findsOneWidget);
    expect(next, findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(of: previous, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.descendant(of: next, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(next);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<IconButton>(
            find.descendant(of: previous, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses direct horizontal scrolling on a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_railApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('test-rail-previous')), findsNothing);
    expect(find.byKey(const ValueKey('test-rail-next')), findsNothing);

    final rail = find.byKey(const ValueKey('test-rail'));
    await tester.drag(rail, const Offset(-240, 0));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: rail, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.pixels, greaterThan(0));
  });
}

Widget _railApp() {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: Center(
        child: PeekHorizontalRail(
          railId: 'test-rail',
          semanticLabel: '测试内容轨',
          height: 120,
          itemCount: 8,
          itemExtent: 180,
          itemBuilder: (context, index) => ColoredBox(
            color: AppColors.surfaceHigh,
            child: Center(child: Text('项目 $index')),
          ),
        ),
      ),
    ),
  );
}
