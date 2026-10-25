import 'dart:async';

import 'package:embyplayer/src/app/app_providers.dart';
import 'package:embyplayer/src/app/peek_pipeline_exerciser.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/features/scrobble/data/bangumi_store.dart';
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

        // Live hardware shader pipeline exerciser. Rendered at real window size
        // and hidden behind the opaque splash: a previous revision squeezed the
        // same content into a 48x48 box, which only compiled the 48px variants
        // and left the real full-size glass/clip pipelines cold.
        if (!_ready)
          const Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: RepaintBoundary(child: PeekPipelineExerciser()),
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
