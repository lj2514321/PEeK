import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
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
    expect(_pageOpacity(tester), 1.0);
  });

  testWidgets('settling neutralises every flight layer', (tester) async {
    final controller = await _pump(tester);

    controller.value = 1;
    await tester.pump();

    expect(find.byKey(const Key('flyer')), findsNothing);
    expect(_pageOpacity(tester), 1.0);
  });

  testWidgets('a page without artwork still fades in', (tester) async {
    final controller = await _pump(tester, withPoster: false);

    controller.value = 0.0;
    await tester.pump();

    expect(find.byKey(const Key('flyer')), findsNothing);
    expect(_pageOpacity(tester), 0);
  });

  testWidgets('publishes activeCardToken while flying and clears on settle', (
    tester,
  ) async {
    final token = Object();
    final controller = await _pump(tester, originCardToken: token);

    controller.value = 0.25;
    await tester.pump();
    expect(PeekSharedFlight.activeCardToken.value, same(token));

    controller.value = 1.0;
    await tester.pump();
    expect(PeekSharedFlight.activeCardToken.value, isNull);
  });

  testWidgets('the flyer dissolves into the page poster, never swaps', (
    tester,
  ) async {
    final controller = await _pump(tester);

    controller.value = 0.95;
    await tester.pump();

    // Both are painted at once: the page's poster underneath, the flyer fading
    // over it. A single-frame swap makes every residual difference — the crop
    // left over from a card that was not 2:3, the halo and shadow the flyer
    // does not carry — jump on the last frame.
    expect(_slotOpacity(tester), 1);
    final flyerOpacity = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.byKey(const Key('flyer')),
            matching: find.byType(Opacity),
          ),
        )
        .first
        .opacity;
    expect(flyerOpacity, lessThan(1));
    expect(flyerOpacity, greaterThan(0));
  });
  testWidgets('clips incoming page container from card rect to full window', (
    tester,
  ) async {
    final controller = await _pump(tester);

    controller.value = 0.0;
    await tester.pump();
    final startClip = _pageClipRect(tester)!;
    _expectRect(startClip.outerRect, _card);

    controller.value = 0.35;
    await tester.pump();
    final midClip = _pageClipRect(tester)!;
    expect(midClip.width, greaterThan(_card.width));
    expect(midClip.width, lessThan(800));

    controller.value = 0.72;
    await tester.pump();
    final lateClip = _pageClipRect(tester)!;
    expect(lateClip.width, greaterThan(midClip.width));
    expect(lateClip.tlRadiusX, closeTo(AppRadius.value, 0.1));

    controller.value = 1.0;
    await tester.pump();
    expect(_pageClipRect(tester), isNull);
  });

  testWidgets(
    'reverse flight shifts destination by scrollOffset or suppresses when scrolled far',
    (tester) async {
      final controller = await _pump(tester);
      controller.value = 1.0;
      await tester.pump();

      final pageContext = tester.element(find.byKey(const Key('page-bg')));
      final scrollNotifier = PeekSharedFlight.scrollOffsetOf(pageContext)!;
      scrollNotifier.value = 100.0;

      // Begin reversing from 1.0 towards 0.0.
      controller.animateBack(0.0, duration: const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3));

      final reverseStart = _paintedRect(tester);
      expect(reverseStart.top, closeTo(_slot.top - 100.0, 12.0));

      // When scrolled past maxReverseFlightScrollOffset (280), flight is suppressed.
      scrollNotifier.value = 360.0;
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.byKey(const Key('flyer')), findsNothing);
      expect(_slotOpacity(tester), 1);
      controller.stop();
    },
  );

  testWidgets(
    'ancestor shell pointer-down does not overwrite card originRect with full-window rect',
    (tester) async {
      final cardToken = Object();
      late BuildContext shellContext;
      late BuildContext cardContext;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1280, 800)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                shellContext = context;
                return SizedBox(
                  width: 1280,
                  height: 800,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 140,
                        top: 220,
                        width: 156,
                        height: 234,
                        child: Builder(
                          builder: (c) {
                            cardContext = c;
                            return const SizedBox.expand();
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Child card records its tap first, then event bubbles up to shell.
      PeekMotionOrigin.recordTap(
        cardContext,
        const Offset(200, 300),
        cardToken: cardToken,
      );
      PeekMotionOrigin.recordTapAlignment(shellContext, const Offset(200, 300));
      PeekMotionOrigin.recordTap(shellContext, const Offset(200, 300));

      expect(PeekMotionOrigin.lastTapRect, _card);
      expect(PeekMotionOrigin.lastTapCardToken, same(cardToken));
    },
  );

  testWidgets(
    'poster flight works seamlessly for 16:9 cards with aspect crop and settles in slot',
    (tester) async {
      // 16:9 card: 320x180
      const bannerRect = Rect.fromLTWH(140, 220, 320, 180);
      final controller = await _pump(
        tester,
        withPoster: true,
        originRect: bannerRect,
      );

      // Frame 0: flyer covers the card
      controller.value = 0.0;
      await tester.pump();
      final startRect = _flyingBoxRect(tester);
      _expectRect(startRect, bannerRect, tolerance: 1.5);
      expect(_slotOpacity(tester), 0);

      // Mid-flight: flying smoothly
      controller.value = 0.5;
      await tester.pump();
      final midRect = _flyingBoxRect(tester);
      expect(midRect.width, greaterThan(startRect.width));
      expect(_slotOpacity(tester), 0);

      // Settled: lands in slot and slot is revealed
      controller.value = 1.0;
      await tester.pump();
      expect(find.byKey(const Key('flyer')), findsNothing);
      expect(_slotOpacity(tester), 1);
    },
  );

  testWidgets(
    'expanding container maintains uniform AppRadius.value for wide banners and cards',
    (tester) async {
      // 16:9 banner: 320x180
      const bannerRect = Rect.fromLTWH(40, 60, 320, 180);
      final controller = await _pump(
        tester,
        withPoster: false,
        originRect: bannerRect,
      );

      for (final raw in const [0.0, 0.25, 0.50, 0.72]) {
        controller.value = raw;
        await tester.pump();
        final clip = _pageClipRect(tester)!;
        expect(
          clip.tlRadiusX,
          closeTo(AppRadius.value, 0.1),
          reason: 'Radius must remain AppRadius.value at progress $raw',
        );
      }
    },
  );
}

Future<AnimationController> _pump(
  WidgetTester tester, {
  bool withPoster = true,
  Object? originCardToken,
  Rect originRect = _card,
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
        originRect: originRect,
        originCardToken: originCardToken,
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

RRect? _pageClipRect(WidgetTester tester) {
  final match = find.ancestor(
    of: find.byKey(const Key('page-bg')),
    matching: find.byType(ClipRRect),
  );
  if (match.evaluate().isEmpty) return null;
  final clipWidget = tester.widget<ClipRRect>(match.first);
  // A `Clip.none` layer paints no clip at all, which is how the settled state
  // stays free while keeping the same widget tree.
  if (clipWidget.clipBehavior == Clip.none) return null;
  final renderBox = tester.renderObject<RenderBox>(match.first);
  return clipWidget.clipper?.getClip(renderBox.size);
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

Rect _flyingBoxRect(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(const Key('flying-poster-box')),
  );
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
