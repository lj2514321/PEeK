// ignore_for_file: avoid_print, prefer_function_declarations_over_variables, unused_local_variable
import 'dart:math' as math;
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/features/details/presentation/detail_hero_layout.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MotionBenchmarkResult {
  MotionBenchmarkResult({
    required this.name,
    required this.frameDurationsMs,
    required this.frameStages,
  });

  final String name;
  final List<double> frameDurationsMs;
  final List<String> frameStages;

  int get totalFrames => frameDurationsMs.length;

  double get minMs =>
      frameDurationsMs.isEmpty ? 0 : frameDurationsMs.reduce(math.min);
  double get maxMs =>
      frameDurationsMs.isEmpty ? 0 : frameDurationsMs.reduce(math.max);
  double get meanMs => frameDurationsMs.isEmpty
      ? 0
      : frameDurationsMs.reduce((a, b) => a + b) / frameDurationsMs.length;

  double percentile(double p) {
    if (frameDurationsMs.isEmpty) return 0;
    final sorted = List<double>.from(frameDurationsMs)..sort();
    final index = (p * (sorted.length - 1)).round();
    return sorted[index];
  }

  double get p50Ms => percentile(0.50);
  double get p90Ms => percentile(0.90);
  double get p95Ms => percentile(0.95);
  double get p99Ms => percentile(0.99);

  int get jankFrames => frameDurationsMs.where((d) => d > 16.66).length;
  double get jankRatio =>
      totalFrames == 0 ? 0 : (jankFrames / totalFrames) * 100;

  int get severeJankFrames => frameDurationsMs.where((d) => d > 33.33).length;

  void printReport() {
    print('================================================================');
    print(' BENCHMARK REPORT: $name');
    print(' Total Frames:       $totalFrames');
    print(' Frame Time Mean:    ${meanMs.toStringAsFixed(2)} ms');
    print(' Frame Time Min:     ${minMs.toStringAsFixed(2)} ms');
    print(' Frame Time P50:     ${p50Ms.toStringAsFixed(2)} ms');
    print(' Frame Time P90:     ${p90Ms.toStringAsFixed(2)} ms');
    print(' Frame Time P95:     ${p95Ms.toStringAsFixed(2)} ms');
    print(' Frame Time Max:     ${maxMs.toStringAsFixed(2)} ms');
    print(
      ' Jank Frames (>16.6ms): $jankFrames / $totalFrames (${jankRatio.toStringAsFixed(1)}%)',
    );
    print(' Severe Jank (>33.3ms): $severeJankFrames / $totalFrames');
    print(' Top 5 Slowest Frames:');
    final indices = List<int>.generate(totalFrames, (i) => i);
    indices.sort((a, b) => frameDurationsMs[b].compareTo(frameDurationsMs[a]));
    for (var i = 0; i < math.min(5, totalFrames); i++) {
      final idx = indices[i];
      print(
        '   #$idx: ${frameDurationsMs[idx].toStringAsFixed(2)} ms [${frameStages[idx]}]',
      );
    }
    print('================================================================');
  }
}

class _BenchmarkFakeService implements MediaLibraryService {
  @override
  Future<MediaItem> getItem(
    AuthenticatedServer account,
    String itemId, {
    bool forceRefresh = false,
  }) async {
    return MediaItem(
      id: itemId,
      name: 'Benchmark Title',
      kind: MediaItemKind.movie,
      overview: 'Overview for benchmark animation performance profiling.',
      productionYear: 2026,
      communityRating: 8.9,
      officialRating: 'PG-13',
      runTime: const Duration(minutes: 124),
      genres: const ['科幻', '剧情', '动作'],
      people: List.generate(
        10,
        (i) => MediaPerson(
          id: 'p$i',
          name: 'Actor $i',
          role: 'Role $i',
          type: 'Actor',
        ),
      ),
    );
  }

  @override
  Future<List<MediaItem>> getSimilar(
    AuthenticatedServer account,
    String itemId, {
    int limit = 12,
    bool forceRefresh = false,
  }) async => List.generate(
    8,
    (i) =>
        MediaItem(id: 'sim-$i', name: 'Similar $i', kind: MediaItemKind.movie),
  );

  @override
  Future<List<MediaItem>> getCollectionItems(
    AuthenticatedServer account,
    String collectionId, {
    int limit = 50,
    bool forceRefresh = false,
  }) async => [];

  @override
  Future<List<MediaItem>> getCollectionsForItem(
    AuthenticatedServer account,
    String itemId, {
    bool forceRefresh = false,
  }) async => [];

  @override
  Future<List<MediaItem>> getEpisodesForSeries(
    AuthenticatedServer account, {
    required String seriesId,
    bool forceRefresh = false,
  }) async => [];

  @override
  Future<MediaPage> getItemsForPerson(
    AuthenticatedServer account, {
    required String personId,
    int startIndex = 0,
    int limit = 40,
    bool forceRefresh = false,
  }) async =>
      const MediaPage(items: [], totalRecordCount: 0, nextStartIndex: 0);

  @override
  Future<void> setFavorite(
    AuthenticatedServer account,
    String itemId, {
    required bool favorite,
  }) async {}

  @override
  Future<void> setPlayed(
    AuthenticatedServer account,
    String itemId, {
    required bool played,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final account = AuthenticatedServer(
    server: DiscoveredServer(
      kind: ServerKind.jellyfin,
      name: 'BenchmarkServer',
      version: '10.11.6',
      serverId: 'server-id',
      apiBaseUri: Uri.parse('http://127.0.0.1:8096'),
    ),
    userId: 'user-id',
    userName: 'Tester',
    deviceId: 'device-id',
    accessToken: 'secret',
  );

  const initialItem = MediaItem(
    id: 'benchmark-movie',
    name: 'Benchmark Movie',
    kind: MediaItemKind.movie,
    overview: 'A movie for stress-testing animations.',
    productionYear: 2026,
    genres: ['Action', 'Sci-Fi'],
  );

  group('Animation Performance Benchmarks', () {
    setUp(() {
      AppMotion.debugOverrideIsTest = false;
    });

    tearDown(() {
      AppMotion.debugOverrideIsTest = null;
    });

    testWidgets('Benchmark: Card to Detail Page Anchor-Morph Expand Transition', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _BenchmarkFakeService();
      final destinationFunc = (Size s) => DetailHeroLayout.of(s).posterRect;
      const originCardRect = Rect.fromLTWH(140, 220, 156, 234);

      late AnimationController animCtrl;
      late AnimationController secAnimCtrl;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mediaLibraryProvider.overrideWithValue(service)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: _TestAnimationHost(
              onInit: (controller, secController) {
                animCtrl = controller;
                secAnimCtrl = secController;
              },
              child: (animation, secondaryAnimation) =>
                  PeekAnchorMorphTransition(
                    animation: animation,
                    secondaryAnimation: secondaryAnimation,
                    originRect: originCardRect,
                    destination: destinationFunc,
                    poster: const DetailPosterArt(item: initialItem),
                    child: MediaDetailPage(
                      account: account,
                      initialItem: initialItem,
                    ),
                  ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Measure Forward Transition (440ms, 28 steps)
      final durations = <double>[];
      final stages = <String>[];
      const totalSteps = 28;

      final sw = Stopwatch();
      for (var i = 0; i <= totalSteps; i++) {
        final progress = i / totalSteps;
        animCtrl.value = progress;

        sw.reset();
        sw.start();
        await tester.pump();
        sw.stop();

        final ms = sw.elapsedMicroseconds / 1000.0;
        durations.add(ms);
        stages.add('Forward t=${progress.toStringAsFixed(2)}');
      }

      final forwardResult = MotionBenchmarkResult(
        name: 'Anchor-Morph Expand (Card -> Detail Page)',
        frameDurationsMs: durations,
        frameStages: stages,
      );
      forwardResult.printReport();

      // Allow settle and post-frame callbacks to finish, simulating real user browsing before hitting back
      await tester.pumpAndSettle();

      // Measure Reverse Transition (Retract 300ms, 19 steps)
      final revDurations = <double>[];
      final revStages = <String>[];
      const revSteps = 19;

      for (var i = revSteps; i >= 0; i--) {
        final progress = i / revSteps;
        animCtrl.value = progress;

        sw.reset();
        sw.start();
        await tester.pump();
        sw.stop();

        final ms = sw.elapsedMicroseconds / 1000.0;
        revDurations.add(ms);
        revStages.add('Reverse t=${progress.toStringAsFixed(2)}');
      }

      final reverseResult = MotionBenchmarkResult(
        name: 'Anchor-Morph Retract (Detail Page -> Card Pop)',
        frameDurationsMs: revDurations,
        frameStages: revStages,
      );
      reverseResult.printReport();

      expect(forwardResult.totalFrames, greaterThan(20));
    });

    testWidgets(
      'Benchmark: Detail Page Content Without Mid-Flight Staging Interruptions',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final destinationFunc = (Size s) => DetailHeroLayout.of(s).posterRect;
        const originCardRect = Rect.fromLTWH(140, 220, 156, 234);

        late AnimationController animCtrl;
        late AnimationController secAnimCtrl;

        // We test a smooth detail page structure where below-the-fold content is held
        // until the flight settles (or static lightweight placeholder), avoiding mid-flight layout spikes.
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: _TestAnimationHost(
                onInit: (controller, secController) {
                  animCtrl = controller;
                  secAnimCtrl = secController;
                },
                child: (animation, secondaryAnimation) =>
                    PeekAnchorMorphTransition(
                      animation: animation,
                      secondaryAnimation: secondaryAnimation,
                      originRect: originCardRect,
                      destination: destinationFunc,
                      poster: const DetailPosterArt(item: initialItem),
                      child: Scaffold(
                        backgroundColor: AppColors.canvas,
                        body: Stack(
                          children: [
                            // Smooth hero & copy
                            Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Row(
                                children: [
                                  const SizedBox(width: 260, height: 390),
                                  const SizedBox(width: 32),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          initialItem.name,
                                          style: const TextStyle(fontSize: 32),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(initialItem.overview ?? ''),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ),
            ),
          ),
        );
        await tester.pump();

        final durations = <double>[];
        final stages = <String>[];
        const totalSteps = 28;

        final sw = Stopwatch();
        for (var i = 0; i <= totalSteps; i++) {
          final progress = i / totalSteps;
          animCtrl.value = progress;

          sw.reset();
          sw.start();
          await tester.pump();
          sw.stop();

          final ms = sw.elapsedMicroseconds / 1000.0;
          durations.add(ms);
          stages.add('Forward t=${progress.toStringAsFixed(2)}');
        }

        final isolatedResult = MotionBenchmarkResult(
          name:
              'Experiment: Pure Anchor Morph Transition (No Heavy Mount Spike)',
          frameDurationsMs: durations,
          frameStages: stages,
        );
        isolatedResult.printReport();
      },
    );
  });
}

class _TestAnimationHost extends StatefulWidget {
  const _TestAnimationHost({required this.onInit, required this.child});

  final void Function(
    AnimationController controller,
    AnimationController secController,
  )
  onInit;
  final Widget Function(
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  )
  child;

  @override
  State<_TestAnimationHost> createState() => _TestAnimationHostState();
}

class _TestAnimationHostState extends State<_TestAnimationHost>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _secController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
    _secController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    widget.onInit(_controller, _secController);
  }

  @override
  void dispose() {
    _controller.dispose();
    _secController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child(_controller, _secController);
  }
}
