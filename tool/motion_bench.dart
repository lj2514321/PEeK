// Profile-mode GPU sampler for the app's glass panels.
//
// Run with:  flutter run --profile -d windows -t tool/motion_bench.dart
//
// It mounts the same primitives the app uses (a full-width top command bar
// blur, a 224px sidebar rail blur, animated content underneath) and reports
// per-scenario build/raster frame timings from SchedulerBinding.
//
// The point is an A/B on blur sigma: on Windows Flutter rasterizes through
// ANGLE -> D3D11, where a backdrop blur costs roughly area * sigma. The app
// currently uses sigma 34 (top bar), 38 (rail, search dropdown), 42 (ambient).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

final List<FrameTiming> _timings = <FrameTiming>[];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addTimingsCallback(_timings.addAll);
  runApp(const _BenchApp());
}

class _BenchApp extends StatefulWidget {
  const _BenchApp();

  @override
  State<_BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<_BenchApp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  double _sigma = 38.0;
  bool _glass = false;
  bool _fullscreenGlass = false;
  bool _animateContent = true;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runScenarios());
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Future<void> _settle() async {
    // Let the new widget subtree build and the shader pipeline stabilize
    // before we start measuring this scenario.
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  Future<void> _measure(String label) async {
    _timings.clear();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final sample = List<FrameTiming>.from(_timings);
    _report(label, sample);
  }

  void _report(String label, List<FrameTiming> sample) {
    if (sample.isEmpty) {
      debugPrint('BENCH ${label.padRight(28)} no frames captured');
      return;
    }
    final build =
        sample.map((t) => t.buildDuration.inMicroseconds / 1000).toList()
          ..sort();
    final raster =
        sample.map((t) => t.rasterDuration.inMicroseconds / 1000).toList()
          ..sort();
    final total = sample.map((t) => t.totalSpan.inMicroseconds / 1000).toList()
      ..sort();
    final span =
        sample.last.timestampInMicroseconds(ui.FramePhase.vsyncStart) -
        sample.first.timestampInMicroseconds(ui.FramePhase.vsyncStart);
    final fps = span <= 0 ? 0.0 : (sample.length - 1) * 1000000 / span;

    String band(List<double> v) {
      double at(double p) => v[((v.length - 1) * p).round()];
      return 'avg ${at(0.5).toStringAsFixed(2)}  '
          'p95 ${at(0.95).toStringAsFixed(2)}  '
          'p99 ${at(0.99).toStringAsFixed(2)}  '
          'max ${v.last.toStringAsFixed(2)}';
    }

    debugPrint(
      'BENCH ${label.padRight(28)} '
      'n=${sample.length.toString().padLeft(3)}  '
      'fps=${fps.toStringAsFixed(1).padLeft(5)}  '
      'build[${band(build)}]  raster[${band(raster)}]  '
      'total p95 ${total[((total.length - 1) * 0.95).round()].toStringAsFixed(2)}',
    );
  }

  Future<void> _runScenarios() async {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    debugPrint(
      'BENCH viewport ${view.physicalSize.width.toInt()}x'
      '${view.physicalSize.height.toInt()} @'
      '${view.devicePixelRatio}x '
      'refresh=${view.display.refreshRate.toStringAsFixed(0)}Hz',
    );

    await _settle();
    await _measure('baseline: no glass, motion');
    await _measure('baseline: no glass, motion (repeat)');

    for (final sigma in <double>[12, 20, 28, 34, 38, 42]) {
      _sigma = sigma;
      _glass = true;
      setState(() {});
      await _settle();
      await _measure('glass sigma ${sigma.toStringAsFixed(0)} (bar+rail)');
    }

    _glass = true;
    _sigma = 38;
    _animateContent = false;
    setState(() {});
    await _settle();
    await _measure('sigma 38, static content');

    _glass = false;
    _fullscreenGlass = true;
    _animateContent = true;
    _sigma = 38;
    setState(() {});
    await _settle();
    await _measure('fullscreen glass sigma 38');

    _sigma = 12;
    setState(() {});
    await _settle();
    await _measure('fullscreen glass sigma 12');

    _fullscreenGlass = false;
    setState(() {});
    await _settle();
    await _measure('fullscreen glass off');

    _glass = false;
    _animateContent = true;
    setState(() {});
    await _settle();
    await _measure('glass off, motion');

    debugPrint('BENCH done');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: const Color(0xFF0B0E16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Content underneath the glass: dense, colorful, moving.
            RepaintBoundary(
              child: !_animateContent
                  ? const _ContentLayer()
                  : AnimatedBuilder(
                      animation: _motion,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, -_motion.value * 1200),
                          child: child,
                        );
                      },
                      child: const _ContentLayer(),
                    ),
            ),
            if (_fullscreenGlass)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma),
                  child: const ColoredBox(color: Color(0x1AFFFFFF)),
                ),
              ),
            if (_glass)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 224,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma),
                    child: const ColoredBox(color: Color(0x1AFFFFFF)),
                  ),
                ),
              ),
            if (_glass)
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: 66,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                    child: const ColoredBox(color: Color(0x1AFFFFFF)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ContentLayer extends StatelessWidget {
  const _ContentLayer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < 26; row++)
          SizedBox(
            height: 96,
            child: Row(
              children: [
                for (var col = 0; col < 8; col++)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.fromARGB(
                              255,
                              40 + ((row * 37 + col * 53) % 200),
                              30 + ((row * 71 + col * 17) % 200),
                              60 + ((row * 23 + col * 91) % 180),
                            ),
                            Color.fromARGB(
                              255,
                              20 + ((row * 13 + col * 29) % 180),
                              50 + ((row * 41 + col * 67) % 160),
                              90 + ((row * 83 + col * 11) % 150),
                            ),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$row:$col',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
