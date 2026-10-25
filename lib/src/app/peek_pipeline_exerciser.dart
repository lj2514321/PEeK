import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/domain/media_item.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:flutter/material.dart';

/// Paints the real destination page once, at real size, through the real
/// transition, so the GPU driver compiles those pipelines before the user
/// clicks anything.
///
/// Measured on Windows (ANGLE/D3D11), first `MediaDetailPage` push through
/// `Peek3DPageRoute`:
///
/// | attempt | build  | raster    | frames > 33 ms |
/// | ------- | ------ | --------- | -------------- |
/// | first   | 36 ms  | **502 ms** | 5             |
/// | second  | 12 ms  | 30 ms      | 2             |
/// | third   | 9 ms   | 14 ms      | 0             |
///
/// Bisecting the spike:
///
/// * ~271 ms — the page's own painting pipelines (still 271 ms with every
///   image removed, so this is not decoding);
/// * ~174 ms — the extra variants the transition composite needs, i.e. glass
///   inside a scaled, anti-aliased rounded clip;
/// * ~57 ms  — the first backdrop image decode.
///
/// The previous exerciser mounted the same page but squeezed it through
/// `FittedBox` into a **48x48** box at 0.005 opacity, so only the 48 px
/// variants were ever compiled. Rendering it at the real window size brings
/// the measured first push down to 20 ms of raster with zero frames over 33 ms
/// (verified with `tool/transition_bench.dart --dart-define=BENCH_WARMUP=push`).
///
/// It is painted fully opaque and simply sits behind the gate's opaque splash,
/// so it never becomes visible. (An `Opacity(0.02)` wrapper was measured to
/// compile a *different* pipeline: the glass then samples an offscreen opacity
/// layer instead of the real scene, leaving ~160 ms of the spike cold.)
class PeekPipelineExerciser extends StatefulWidget {
  const PeekPipelineExerciser({super.key});

  @override
  State<PeekPipelineExerciser> createState() => _PeekPipelineExerciserState();
}

class _PeekPipelineExerciserState extends State<PeekPipelineExerciser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  bool _done = false;

  /// A page-shaped payload: the page renders its hero, glass panels, spec
  /// grids and rails without touching the network.
  static const MediaItem _warmupItem = MediaItem(
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
      MediaPerson(
        id: 'warmup-p1',
        name: 'Director One',
        role: 'Director',
        type: 'Director',
      ),
      MediaPerson(
        id: 'warmup-p2',
        name: 'Lead Actor',
        role: 'Protagonist',
        type: 'Actor',
      ),
    ],
    chapters: [MediaChapter(name: 'Chapter 1', startPosition: Duration.zero)],
  );

  @override
  void initState() {
    super.initState();
    _ticker =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 520),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            _ticker.stop();
            // The transition drops its anti-aliased rounded clip once it
            // completes, which re-rasterizes the page unclipped. Keep painting
            // for two more frames so that state is compiled too — measured as
            // a 142 ms frame at the end of the first real transition.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _done = true);
              });
            });
          }
        });
    _ticker.forward();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.canvas),
          PeekSpatialTransition(
            animation: _ticker,
            secondaryAnimation: kAlwaysDismissedAnimation,
            originAlignment: Alignment.center,
            child: const MediaDetailPage(
              account: null,
              initialItem: _warmupItem,
              isWarmup: true,
            ),
          ),
        ],
      ),
    );
  }
}
