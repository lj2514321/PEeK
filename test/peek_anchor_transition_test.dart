import 'package:embyplayer/src/core/presentation/peek_anchor_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 2:3 card in a grid, and the 2:3 poster slot a detail page reserves for it.
/// Same aspect on purpose: that is the case the flight is allowed to run in, and
/// it is what makes the scale uniform.
const Rect _card = Rect.fromLTWH(140, 220, 156, 234);
const Rect _slot = Rect.fromLTWH(68, 76, 360, 540);

void main() {
  testWidgets('the artwork starts exactly on the pressed card', (tester) async {
    final controller = await _pump(tester);

    controller.value = 0;
    await tester.pump();

    _expectRect(_paintedRect(tester), _card);
  });

  testWidgets('the artwork travels to the poster slot', (tester) async {
    final controller = await _pump(tester);

    controller.value = 0.99;
    await tester.pump();

    _expectRect(_paintedRect(tester), _slot, tolerance: 2);
  });

  testWidgets('the flight grows monotonically and never leaves 2:3', (
    tester,
  ) async {
    final controller = await _pump(tester);
    final widths = <double>[];
    final distances = <double>[];

    for (final raw in const [0.0, 0.25, 0.5, 0.75, 0.95]) {
      controller.value = raw;
      await tester.pump();
      final painted = _paintedRect(tester);
      widths.add(painted.width);
      distances.add((painted.center - _slot.center).distance);
      expect(
        painted.width / painted.height,
        closeTo(2 / 3, 0.005),
        reason: 'a uniform scale must keep the card aspect ratio at $raw',
      );
    }

    for (var i = 1; i < widths.length; i++) {
      expect(widths[i], greaterThan(widths[i - 1]));
      expect(distances[i], lessThan(distances[i - 1]));
    }
  });

  testWidgets('the page keeps its slot but stops painting it while flying', (
    tester,
  ) async {
    final controller = await _pump(tester);

    controller.value = 0.3;
    await tester.pump();
    expect(_slotOpacity(tester), 0);

    controller.value = 1;
    await tester.pump();
    expect(_slotOpacity(tester), 1);
  });

  testWidgets('the page fades in behind the flight', (tester) async {
    final controller = await _pump(tester);

    controller.value = 0;
    await tester.pump();
    expect(_pageOpacity(tester), 0);

    controller.value = 0.3;
    await tester.pump();
    final mid = _pageOpacity(tester)!;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));

    controller.value = 0.62;
    await tester.pump();
    // Fully faded in by the end of the window, where the layer is dropped
    // entirely rather than kept as an `Opacity(1)`.
    expect(_pageOpacity(tester), isNull);
  });

  testWidgets('settling leaves no flight layers behind', (tester) async {
    final controller = await _pump(tester);

    controller.value = 1;
    await tester.pump();

    expect(find.byKey(const Key('flyer')), findsNothing);
    expect(_pageOpacity(tester), isNull);
  });

  testWidgets('a page without artwork still fades in', (tester) async {
    final controller = await _pump(tester, withPoster: false);

    controller.value = 0.0;
    await tester.pump();

    expect(find.byKey(const Key('flyer')), findsNothing);
    expect(_pageOpacity(tester), 0);
  });
}

Future<AnimationController> _pump(
  WidgetTester tester, {
  bool withPoster = true,
}) async {
  final controller = AnimationController(
    vsync: const TestVSync(),
    duration: const Duration(milliseconds: 460),
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: PeekAnchorMorphTransition(
        animation: controller,
        secondaryAnimation: const AlwaysStoppedAnimation<double>(0),
        originRect: _card,
        destination: (_) => _slot,
        poster: withPoster
            ? const ColoredBox(key: Key('flyer'), color: Color(0xFF33CC66))
            : null,
        child: const _FakePage(),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

/// The artwork's rectangle in screen space, transforms included — i.e. what the
/// user actually sees, not where the widget was laid out.
Rect _paintedRect(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(find.byKey(const Key('flyer')));
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

double? _pageOpacity(WidgetTester tester) {
  final match = find.ancestor(
    of: find.byKey(const Key('page-bg')),
    matching: find.byType(Opacity),
  );
  if (match.evaluate().isEmpty) return null;
  return tester.widget<Opacity>(match.first).opacity;
}

double? _slotOpacity(WidgetTester tester) {
  final match = find.byKey(const Key('slot-opacity'));
  if (match.evaluate().isEmpty) return null;
  return tester.widget<Opacity>(match).opacity;
}

void _expectRect(Rect actual, Rect expected, {double tolerance = 0.6}) {
  expect(actual.left, closeTo(expected.left, tolerance));
  expect(actual.top, closeTo(expected.top, tolerance));
  expect(actual.width, closeTo(expected.width, tolerance));
  expect(actual.height, closeTo(expected.height, tolerance));
}

/// Only the two pieces of the contract the route relies on: the page reads the
/// flight flag, and it keeps the poster it is told not to paint.
class _FakePage extends StatelessWidget {
  const _FakePage();

  @override
  Widget build(BuildContext context) {
    final flying = PeekSharedFlight.flyingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(key: Key('page-bg'), color: Color(0xFF0B0E16)),
        if (flying != null)
          ValueListenableBuilder<bool>(
            valueListenable: flying,
            builder: (context, flying, child) => Opacity(
              key: const Key('slot-opacity'),
              opacity: flying ? 0 : 1,
              child: child,
            ),
            child: const SizedBox(width: 360, height: 540),
          ),
      ],
    );
  }
}
