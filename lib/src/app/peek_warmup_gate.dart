import 'dart:async';
import 'dart:ui' as ui;

import 'package:embyplayer/src/app/app_providers.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/scrobble/data/bangumi_store.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Preloads and compiles all Skia shaders, typography atlases, and system caches
/// during application startup, eliminating all initial-load animation jank.
class PeekWarmupGate extends ConsumerStatefulWidget {
  const PeekWarmupGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PeekWarmupGate> createState() => _PeekWarmupGateState();
}

class _PeekWarmupGateState extends ConsumerState<PeekWarmupGate> {
  bool _ready = false;
  bool _dismantled = false;

  @override
  void initState() {
    super.initState();
    if (AppMotion.isTest) {
      _ready = true;
      _dismantled = true;
      return;
    }
    _runStartupWarmup();
  }

  Future<void> _runStartupWarmup() async {
    // 1. Asynchronously pre-hydrate session, settings, and library caches
    final prewarmFuture = Future.wait([
      ref.read(serverAuthenticationProvider).restoreSessionState(),
      ref.read(localMediaLibraryProvider).getLibraries(),
      ref.read(playbackSettingsStoreProvider).read(),
      BangumiStore.prewarm(),
    ]);

    // 2. Guarantee a smooth, non-jarring lead-in window (520ms) for Direct3D 11/Skia
    // to compile all hardware shaders and layout the primary surface quietly.
    final timerFuture = Future<void>.delayed(const Duration(milliseconds: 520));

    try {
      await Future.wait([prewarmFuture, timerFuture]);
    } catch (_) {
      // Non-fatal if session or network error; proceed to UI cleanly
    }

    if (!mounted) return;
    setState(() => _ready = true);

    // Wait for the 360ms cinemaFade exit transition to finish before dismantling overlay
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() => _dismantled = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isTest || _dismantled) {
      return widget.child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // The real primary tree kept mounted underneath so initial layout occurs
        // before the splash fades away.
        widget.child,

        // Live hardware shader pipeline exerciser (renders inside the active Direct3D viewport).
        // Positioned inside the window bounds (0, 0, 48, 48), safely hidden behind the opaque
        // splash view, ensuring Flutter's PaintingContext traverser does not cull it.
        if (!_ready)
          const Positioned(
            left: 0,
            top: 0,
            width: 48,
            height: 48,
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: _HardwarePipelineExerciser(),
                ),
              ),
            ),
          ),

        // High-aesthetic VisionOS splash screen overlay
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchOutCurve: PeekCurves.cinemaFade,
          child: _ready
              ? const SizedBox.shrink()
              : const _VisionWarmupSplashView(),
        ),
      ],
    );
  }
}

/// Renders all blur sigmas, 3D matrices, gradients, and font glyphs into the
/// live Direct3D viewport, forcing the GPU driver to compile all HLSL shaders.
class _HardwarePipelineExerciser extends StatefulWidget {
  const _HardwarePipelineExerciser();

  @override
  State<_HardwarePipelineExerciser> createState() =>
      _HardwarePipelineExerciserState();
}

class _HardwarePipelineExerciserState extends State<_HardwarePipelineExerciser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  static const _warmupDetailItem = MediaItem(
    id: '__peek_warmup_detail_item__',
    name: 'PEeK Spatial Warmup Title',
    kind: MediaItemKind.movie,
    overview: '预热详情页排版、阴影、渐变与空间缩放过渡渲染管线。',
    productionYear: 2026,
    communityRating: 8.8,
    officialRating: 'PG-13',
    runTime: Duration(hours: 2, minutes: 18),
    genres: ['Sci-Fi', 'Drama', 'Adventure'],
    people: [
      MediaPerson(id: 'warmup-p1', name: 'Director One', role: 'Director', type: 'Director'),
      MediaPerson(id: 'warmup-p2', name: 'Lead Actor', role: 'Protagonist', type: 'Actor'),
    ],
    chapters: [
      MediaChapter(name: 'Chapter 1', startPosition: Duration.zero),
    ],
  );

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        return Opacity(
          opacity: 0.005 + (_ticker.value * 0.005),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              children: [
                // Base colored canvas ensuring BackdropFilter has non-zero pixels to sample & blur
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF38BDF8),
                          Color(0xFF6366F1),
                          Color(0xFFE11D48),
                        ],
                      ),
                    ),
                  ),
                ),

                // 1. All blur sigmas used in the application across decal & mirror modes
                for (final sigma in [
                  5.0,
                  18.0,
                  24.0,
                  28.0,
                  30.0,
                  32.0,
                  34.0,
                  38.0,
                  42.0,
                ])
                  BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: sigma,
                      sigmaY: sigma,
                      tileMode: TileMode.decal,
                    ),
                    child: const SizedBox(width: 8, height: 8),
                  ),
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 42,
                    sigmaY: 42,
                    tileMode: TileMode.mirror,
                  ),
                  child: const ColoredBox(
                    color: Color(0xFF38BDF8),
                    child: SizedBox(width: 12, height: 12),
                  ),
                ),
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      width: 1120,
                      height: 720,
                      child: PeekSpatialTransition(
                        animation: _ticker,
                        secondaryAnimation: kAlwaysDismissedAnimation,
                        originAlignment: Alignment.center,
                        child: const MediaDetailPage(
                          account: null,
                          initialItem: _warmupDetailItem,
                          isWarmup: true,
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. 3D perspective tilt matrix & animated breathing scale
                Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX(0.05 * _ticker.value)
                    ..rotateY(0.05 * _ticker.value)
                    ..scaleByDouble(
                      1.0 + (0.038 * _ticker.value),
                      1.0 + (0.038 * _ticker.value),
                      1.0,
                      1.0,
                    ),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 42,
                          offset: Offset(0, 18),
                        ),
                        BoxShadow(color: Color(0x2238BDF8), blurRadius: 32),
                        BoxShadow(color: Color(0x33FFFFFF), blurRadius: 14),
                      ],
                    ),
                  ),
                ),

                // 3. VisionOS ambient theme gradients & cinematic vignettes
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xF5080B12),
                        Color(0xD8080B12),
                        Color(0x75080B12),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.38, 0.65, 1.0],
                    ),
                  ),
                  child: SizedBox(width: 10, height: 10),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.38, -0.48),
                      radius: 1.15,
                      colors: [Color(0x886B421B), Colors.transparent],
                    ),
                  ),
                  child: SizedBox(width: 10, height: 10),
                ),

                // 4. Core font and icon glyphs atlas pre-rasterization
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'PEeK 空间流体 正在就绪 媒体库 首页 收藏 设置 演员 播放 暂停 继续观看 最新上线 推荐 全部 详情 电影 剧集 季 集 4K HDR Atmos 0123456789',
                    ),
                    Icon(Icons.movie_outlined),
                    Icon(Icons.video_library_rounded),
                    Icon(Icons.favorite_rounded),
                    Icon(Icons.tune_rounded),
                    Icon(Icons.people_rounded),
                    Icon(Icons.play_arrow_rounded),
                    Icon(Icons.star_rounded),
                    Icon(Icons.search_rounded),
                    Icon(Icons.chevron_left_rounded),
                    Icon(Icons.chevron_right_rounded),
                    Icon(Icons.info_outline_rounded),
                    Icon(Icons.close_rounded),
                    Icon(Icons.crop_square_rounded),
                    Icon(Icons.remove_rounded),
                    Icon(Icons.auto_awesome_rounded),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// VisionOS-grade frosted dark glass splash screen.
class _VisionWarmupSplashView extends StatelessWidget {
  const _VisionWarmupSplashView();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF090D16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background ambient gradient wash
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.2),
                radius: 0.9,
                colors: [
                  const Color(0xFF38BDF8).withValues(alpha: 0.12),
                  const Color(0xFF581C87).withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Center branding and status
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glass logo container
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.24),
                        blurRadius: 36,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 42,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // Title typography
                const Text(
                  'PEeK',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1.0,
                    ),
                  ),
                  child: const Text(
                    'SPATIAL MOTION ENGINE · 2026',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Fluid progress line
                SizedBox(
                  width: 140,
                  height: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                const Text(
                  '正在预热图形管线与媒体服务...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
