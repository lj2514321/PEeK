// Profile-mode sampler for the "first entry is janky" report.
//
// Run with:  flutter run --profile -d windows -t tool/transition_bench.dart
//
// Pushes the real `MediaDetailPage` through the real `Peek3DPageRoute`
// transition three times in one process and reports each attempt's frames. The
// signal is attempt #1 versus #2/#3: anything much worse the first time is a
// one-time cost (page build, image decode or shader/pipeline compilation), not
// a steady-state rendering problem.
//
// Switches (compile-time defines):
//   --dart-define=BENCH_MODE=spatial|fade|blank
//     spatial (default) the real transition + the real page
//     fade              a plain fade route + the real page
//     blank             the real transition + a blank page
//   --dart-define=BENCH_NO_IMAGE=true
//     strips every image from the fixture, to tell "first decode" apart from
//     "first shader compile".
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/app_providers.dart';
import 'package:embyplayer/src/app/peek_detail_prewarm.dart';
import 'package:embyplayer/src/app/peek_pipeline_exerciser.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/domain/media_item.dart';
import 'package:embyplayer/src/core/domain/server.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final List<FrameTiming> _timings = <FrameTiming>[];

const String _mode = String.fromEnvironment(
  'BENCH_MODE',
  defaultValue: 'spatial',
);

const bool _noImages = bool.fromEnvironment('BENCH_NO_IMAGE');

/// Prints every frame of the first push, to see *where* the spike sits.
const bool _trace = bool.fromEnvironment('BENCH_TRACE');

/// Pushes and pops the page once before measuring, to prove how much of the
/// first-entry spike a prewarm can remove.
const String _warmupMode = String.fromEnvironment('BENCH_WARMUP');

final AuthenticatedServer _account = AuthenticatedServer(
  server: DiscoveredServer(
    kind: ServerKind.jellyfin,
    name: 'Bench',
    version: '10.11.6',
    serverId: 'bench-server',
    apiBaseUri: Uri(scheme: 'http', host: '127.0.0.1', port: 8096),
  ),
  userId: 'bench-user',
  userName: 'Bench',
  deviceId: 'bench-device',
  accessToken: 'bench-token',
);

Route<void> _routeFor(MediaItem detail) {
  Widget page() {
    if (_mode == 'blank') {
      return const ColoredBox(color: Color(0xFF101318));
    }
    return MediaDetailPage(account: _account, initialItem: detail);
  }

  if (_mode == 'fade') {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => page(),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }
  return Peek3DPageRoute(builder: (_) => page());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addTimingsCallback(_timings.addAll);

  final assets = await _makeAssets();
  final detail = _detailItem(assets);
  debugPrint('BENCH mode=$_mode noImages=$_noImages');
  runApp(
    ProviderScope(
      overrides: [
        mediaLibraryProvider.overrideWithValue(_BenchLibrary(detail, assets)),
      ],
      child: _BenchApp(detail: detail),
    ),
  );
}

class _Assets {
  const _Assets({required this.backdrop, required this.poster});
  final Uri backdrop;
  final Uri poster;
}

/// Real files on disk so the first render pays a genuine image decode, the way
/// a server backdrop does.
Future<_Assets> _makeAssets() async {
  final dir = Directory('build${Platform.pathSeparator}bench_assets')
    ..createSync(recursive: true);
  final backdrop = await _writePng(
    File('${dir.path}${Platform.pathSeparator}backdrop.png'),
    1920,
    1080,
    const ui.Color(0xFF1B2A4A),
    const ui.Color(0xFF7A3B2E),
  );
  final poster = await _writePng(
    File('${dir.path}${Platform.pathSeparator}poster.png'),
    600,
    900,
    const ui.Color(0xFF2E1B3A),
    const ui.Color(0xFFBF7A4A),
  );
  return _Assets(backdrop: backdrop, poster: poster);
}

Future<Uri> _writePng(
  File file,
  int width,
  int height,
  ui.Color a,
  ui.Color b,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final rect = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  canvas.drawRect(
    rect,
    ui.Paint()
      ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [a, b]),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  file.writeAsBytesSync(data!.buffer.asUint8List());
  return file.uri;
}

MediaItem _detailItem(_Assets assets) {
  final Uri? poster = _noImages ? null : assets.poster;
  final Uri? backdrop = _noImages ? null : assets.backdrop;
  return MediaItem(
    id: 'bench-movie',
    name: 'Sample Feature 样例电影',
    kind: MediaItemKind.movie,
    overview: '用于压测详情页首次渲染的剧情简介，包含足够多的文字以撑开布局。' * 6,
    productionYear: 2024,
    runTime: const Duration(hours: 2, minutes: 18),
    communityRating: 8.6,
    officialRating: 'PG-13',
    tagline: 'The city remembers.',
    genres: const ['科幻', '剧情', '悬疑', '冒险'],
    tags: const ['赛博朋克', '反乌托邦', '视觉奇观', '长镜头'],
    imageUri: poster,
    backdropUri: backdrop,
    videoCodec: 'hevc',
    container: 'mkv',
    width: 3840,
    height: 2160,
    bitrate: 24000000,
    chapters: [
      for (var i = 0; i < 8; i++)
        MediaChapter(
          name: 'Chapter ${i + 1}',
          startPosition: Duration(minutes: 15 * i),
        ),
    ],
    people: [
      for (var i = 0; i < 10; i++)
        MediaPerson(
          id: 'person-$i',
          name: 'Actor ${i + 1}',
          type: 'Actor',
          role: 'Role ${i + 1}',
          imageUri: poster,
        ),
    ],
    mediaSources: const [
      MediaSourceInfo(
        id: 'source-1',
        name: '4K HDR',
        container: 'mkv',
        fileSize: 24000000000,
        bitrate: 24000000,
        width: 3840,
        height: 2160,
        videoCodec: 'hevc',
        videoRange: 'HDR10',
        audioCodec: 'eac3',
        path: '/media/sample.mkv',
      ),
    ],
  );
}

class _BenchLibrary extends MediaLibraryService {
  _BenchLibrary(this.detail, this.assets) : super(Dio());

  final MediaItem detail;
  final _Assets assets;

  @override
  Future<MediaItem> getItem(
    AuthenticatedServer account,
    String itemId, {
    bool forceRefresh = false,
  }) async {
    return detail;
  }

  @override
  Future<List<MediaItem>> getSimilar(
    AuthenticatedServer account,
    String itemId, {
    int limit = 12,
    bool forceRefresh = false,
  }) async {
    return [
      for (var i = 0; i < 8; i++)
        MediaItem(
          id: 'similar-$i',
          name: 'Similar ${i + 1}',
          kind: MediaItemKind.movie,
          productionYear: 2020 + i,
          communityRating: 7.0 + i / 10,
          imageUri: _noImages ? null : assets.poster,
        ),
    ];
  }

  @override
  Future<List<MediaItem>> getEpisodesForSeries(
    AuthenticatedServer account, {
    required String seriesId,
    bool forceRefresh = false,
  }) async {
    return const <MediaItem>[];
  }

  @override
  Future<List<MediaItem>> getCollectionsForItem(
    AuthenticatedServer account,
    String itemId, {
    bool forceRefresh = false,
  }) async {
    return const <MediaItem>[];
  }

  @override
  Future<List<MediaItem>> getCollectionItems(
    AuthenticatedServer account,
    String collectionId, {
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    return const <MediaItem>[];
  }
}

class _BenchApp extends StatefulWidget {
  const _BenchApp({required this.detail});

  final MediaItem detail;

  @override
  State<_BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<_BenchApp> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  final GlobalKey _homeKey = GlobalKey();
  bool _showExerciser = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    debugPrint('BENCH pushing the detail page 3x');
    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (_warmupMode == 'push') {
      _timings.clear();
      _navigator.currentState!.push<void>(_routeFor(widget.detail));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      _report('warmup push (discarded)', List<FrameTiming>.of(_timings));
      _navigator.currentState!.pop();
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    // "exerciser", "prewarm" or "exerciser+prewarm": each can be measured
    // alone or stacked, which is the only way to know whether they compound.
    if (_warmupMode.contains('exerciser')) {
      _timings.clear();
      setState(() => _showExerciser = true);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      setState(() => _showExerciser = false);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _report('exerciser frames (discarded)', List<FrameTiming>.of(_timings));
    }
    if (_warmupMode.contains('prewarm')) {
      _timings.clear();
      final context = _homeKey.currentContext;
      if (context != null && context.mounted) {
        PeekDetailPrewarm.schedule(context, item: widget.detail);
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      _report('hover prewarm (discarded)', List<FrameTiming>.of(_timings));
    }

    for (var attempt = 1; attempt <= 3; attempt++) {
      _timings.clear();
      _navigator.currentState!.push<void>(_routeFor(widget.detail));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      _report('$_mode push #$attempt', List<FrameTiming>.of(_timings));
      if (_trace && attempt == 1) {
        final sample = List<FrameTiming>.of(_timings);
        for (var i = 0; i < sample.length; i++) {
          debugPrint(
            'TRACE #$i build='
            '${(sample[i].buildDuration.inMicroseconds / 1000).toStringAsFixed(1)} '
            'raster='
            '${(sample[i].rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)}',
          );
        }
      }

      _navigator.currentState!.pop();
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }

    debugPrint('BENCH done');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  void _report(String label, List<FrameTiming> sample) {
    if (sample.isEmpty) {
      debugPrint('BENCH ${label.padRight(22)} no frames');
      return;
    }
    final build = sample
        .map((t) => t.buildDuration.inMicroseconds / 1000)
        .toList();
    final raster = sample
        .map((t) => t.rasterDuration.inMicroseconds / 1000)
        .toList();
    final total = sample.map((t) => t.totalSpan.inMicroseconds / 1000).toList();

    double maxOf(List<double> v) => v.reduce((a, b) => a > b ? a : b);
    int over(List<double> v, double ms) => v.where((d) => d > ms).length;

    final worst = <String>[];
    final ordered = List<int>.generate(sample.length, (i) => i)
      ..sort((a, b) => total[b].compareTo(total[a]));
    for (final i in ordered.take(3)) {
      worst.add(
        '#$i build=${build[i].toStringAsFixed(1)} '
        'raster=${raster[i].toStringAsFixed(1)} '
        'total=${total[i].toStringAsFixed(1)}',
      );
    }

    debugPrint(
      'BENCH ${label.padRight(22)} n=${sample.length.toString().padLeft(3)}  '
      'maxBuild=${maxOf(build).toStringAsFixed(1)}  '
      'maxRaster=${maxOf(raster).toStringAsFixed(1)}  '
      'maxTotal=${maxOf(total).toStringAsFixed(1)}  '
      'frames>16.7ms=${over(total, 16.7)}  '
      'frames>33ms=${over(total, 33)}  '
      '| worst: ${worst.join('  ')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: ColoredBox(
        key: _homeKey,
        color: const Color(0xFF0B0E16),
        child: const Center(
          child: Text(
            'transition bench',
            style: TextStyle(color: Colors.white70, fontSize: 18),
          ),
        ),
      ),
    );
    if (!_showExerciser) return app;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          app,
          const Positioned.fill(child: PeekPipelineExerciser()),
        ],
      ),
    );
  }
}
