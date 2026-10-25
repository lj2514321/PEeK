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

  // Regression guard for the "dead frame" defect: the previous implementation
  // called `animateTo` for every wheel packet, which started a fresh
  // AnimationController that reports t=0 on its first tick. That froze the
  // frame in which a packet landed: 50% of frames were dead when packets
  // arrived every other frame, and 100% were dead (scroll completely frozen)
  // when a packet arrived on every frame. A steady spring must keep moving.
  group('wheel burst continuity', () {
    for (final cadence in <int>[1, 2, 4]) {
      testWidgets('keeps moving when a packet lands every $cadence frame(s)', (
        tester,
      ) async {
        final burst = await _pumpWheelBurst(
          tester,
          packetEveryNFrames: cadence,
        );

        expect(
          burst.deadFrameRatio,
          lessThan(0.02),
          reason:
              'Frames with no movement while wheel packets kept arriving '
              '(the old animateTo model failed here):\n${burst.report()}',
        );
        expect(
          burst.moved,
          greaterThan(burst.naiveDistance * 0.5),
          reason:
              'A continuous burst must actually cover distance; a frozen '
              'scroll moves 0.\n${burst.report()}',
        );
      });
    }

    testWidgets('lands exactly on the accumulated target and stops', (
      tester,
    ) async {
      final controller = await _pumpScrollable(tester);
      final position = controller.position as SmoothScrollPosition;

      const packets = 12;
      const delta = 60.0;
      // The public knob is the single source of truth for speed.
      final expected = packets * delta * position.scrollSpeedMultiplier;

      for (var i = 0; i < packets; i++) {
        position.pointerScroll(delta);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Let the spring settle.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(position.pixels, closeTo(expected, 0.001));

      // Once settled it must stay put (no residual creep or oscillation).
      final settled = position.pixels;
      await tester.pump(const Duration(milliseconds: 400));
      expect(position.pixels, settled);

      controller.dispose();
    });

    testWidgets('clamps at the end of the content instead of overscrolling', (
      tester,
    ) async {
      final controller = await _pumpScrollable(tester, itemCount: 30);
      final position = controller.position as SmoothScrollPosition;

      expect(position.maxScrollExtent, greaterThan(0.0));

      for (var i = 0; i < 40; i++) {
        position.pointerScroll(200.0);
        await tester.pump(const Duration(milliseconds: 16));
      }

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(position.pixels, position.maxScrollExtent);

      final settled = position.pixels;
      await tester.pump(const Duration(milliseconds: 400));
      expect(position.pixels, settled);

      controller.dispose();
    });
  });
}

/// Builds a 100 (or [itemCount]) item list wrapped in [PeekSmoothScroll] and
/// returns its attached controller.
Future<SmoothScrollController> _pumpScrollable(
  WidgetTester tester, {
  int itemCount = 100,
}) async {
  final controller = SmoothScrollController();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PeekSmoothScroll(
          controller: controller,
          child: ListView.builder(
            controller: controller,
            itemCount: itemCount,
            itemBuilder: (context, index) =>
                SizedBox(height: 50, child: Text('Item $index')),
          ),
        ),
      ),
    ),
  );
  expect(controller.hasClients, isTrue);
  return controller;
}

/// Sends one wheel packet every [packetEveryNFrames] frames and records the
/// scroll offset after each frame.
Future<_WheelBurst> _pumpWheelBurst(
  WidgetTester tester, {
  required int packetEveryNFrames,
  int frames = 96,
  double deltaPerPacket = 60.0,
}) async {
  // Long enough that a 96-frame burst cannot reach the end of the list: hitting
  // the extent would look like dead frames and mask the real signal.
  final controller = await _pumpScrollable(tester, itemCount: 4000);
  final position = controller.position as SmoothScrollPosition;

  final pixels = <double>[position.pixels];
  final packetFrames = <int>[];
  for (var frame = 1; frame <= frames; frame++) {
    if (frame % packetEveryNFrames == 0) {
      position.pointerScroll(deltaPerPacket);
      packetFrames.add(frame);
    }
    await tester.pump(const Duration(milliseconds: 16));
    pixels.add(position.pixels);
  }

  final burst = _WheelBurst(
    packets: packetFrames.length,
    deltaPerPacket: deltaPerPacket,
    pixels: pixels,
    packetFrames: packetFrames,
  );
  controller.dispose();
  return burst;
}

class _WheelBurst {
  _WheelBurst({
    required this.packets,
    required this.deltaPerPacket,
    required this.pixels,
    required this.packetFrames,
  });

  final int packets;
  final double deltaPerPacket;
  final List<double> pixels;

  /// 1-based frame number on which each packet was sent.
  final List<int> packetFrames;

  List<double> get _deltas => <double>[
    for (var i = 1; i < pixels.length; i++) pixels[i] - pixels[i - 1],
  ];

  double get moved => pixels.last - pixels.first;

  /// Distance implied by the raw input, before the speed multiplier.
  double get naiveDistance => packets * deltaPerPacket;

  /// Frames that produced no movement *after* the first packet arrived.
  int get _deadFrames {
    final deltas = _deltas;
    if (packetFrames.isEmpty) return deltas.length;
    var dead = 0;
    for (var i = packetFrames.first - 1; i < deltas.length; i++) {
      if (deltas[i].abs() < 0.5) dead++;
    }
    return dead;
  }

  double get deadFrameRatio {
    final deltas = _deltas;
    final considered = packetFrames.isEmpty
        ? deltas.length
        : deltas.length - (packetFrames.first - 1);
    return considered == 0 ? 0 : _deadFrames / considered;
  }

  String report() {
    final deltas = _deltas;
    const ramp = ' .:-=+*#%@';
    final maxDelta = deltas.fold<double>(0, (a, b) => b > a ? b : a);
    final sparkline = StringBuffer();
    for (final d in deltas.take(64)) {
      final level = maxDelta == 0
          ? 0
          : (d / maxDelta * (ramp.length - 1)).round();
      sparkline.write(ramp[level.clamp(0, ramp.length - 1)]);
    }
    return 'packets=$packets  dead=${(_deadFrames)}/${deltas.length}  '
        'moved=${moved.toStringAsFixed(0)}px  '
        'naive=${naiveDistance.toStringAsFixed(0)}px\n'
        'displacement per frame: |$sparkline|'
        '  (space = frame with no movement)';
  }
}
