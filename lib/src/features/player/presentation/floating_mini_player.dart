import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/player/presentation/global_playback_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

class FloatingMiniPlayer extends ConsumerStatefulWidget {
  const FloatingMiniPlayer({super.key});

  static const double miniWidth = 360.0;
  static const double miniHeight = 202.5; // 16:9 standard ratio

  @override
  ConsumerState<FloatingMiniPlayer> createState() => _FloatingMiniPlayerState();
}

class _FloatingMiniPlayerState extends ConsumerState<FloatingMiniPlayer> {
  Offset? _position;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalPlaybackCoordinatorProvider);
    final coordinator = ref.read(globalPlaybackCoordinatorProvider.notifier);

    if (state.mode != PlaybackPresentationMode.mini ||
        state.runtime == null ||
        state.item == null) {
      return const Positioned(width: 0, height: 0, child: SizedBox.shrink());
    }

    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    // Default position: bottom-right corner
    final defaultX = screenSize.width - FloatingMiniPlayer.miniWidth - 28.0;
    final defaultY = screenSize.height - FloatingMiniPlayer.miniHeight - 28.0 - padding.bottom;

    final currentPos = _position ?? Offset(defaultX, defaultY);

    // Clamp inside screen bounds
    final clampedX = currentPos.dx.clamp(
      12.0,
      (screenSize.width - FloatingMiniPlayer.miniWidth - 12.0).clamp(12.0, double.infinity),
    );
    final clampedY = currentPos.dy.clamp(
      padding.top + 12.0,
      (screenSize.height - FloatingMiniPlayer.miniHeight - 12.0).clamp(12.0, double.infinity),
    );

    return Positioned(
      left: clampedX,
      top: clampedY,
      width: FloatingMiniPlayer.miniWidth,
      height: FloatingMiniPlayer.miniHeight,
      child: Material(
        type: MaterialType.transparency,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _position = Offset(
                  clampedX + details.delta.dx,
                  clampedY + details.delta.dy,
                );
              });
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppColors.spotlight.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Video Surface with tap-to-expand
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => coordinator.expand(context),
                      child: Container(
                        color: Colors.black,
                        child: state.runtime!.buildVideoSurface(
                          subtitleConfiguration: const SubtitleViewConfiguration(
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              shadows: [
                                Shadow(blurRadius: 4, color: Colors.black),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Hover Controls Overlay
                    IgnorePointer(
                      ignoring: !_isHovered,
                      child: AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xA6000000),
                            Color(0x55000000),
                            Color(0xB3000000),
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Top bar
                          Positioned(
                            top: 8,
                            left: 12,
                            right: 8,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    state.item!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey('mini-player-expand'),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: '还原全屏播放',
                                  icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 20),
                                  onPressed: () => coordinator.expand(context),
                                ),
                                IconButton(
                                  key: const ValueKey('mini-player-close'),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: '关闭播放',
                                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                                  onPressed: () => coordinator.close(),
                                ),
                              ],
                            ),
                          ),

                          // Center Controls
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: const ValueKey('mini-player-seek-back'),
                                  tooltip: '快退 10 秒',
                                  icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 24),
                                  onPressed: () => coordinator.seekRelative(const Duration(seconds: -10)),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.spotlight.withValues(alpha: 0.85),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    key: const ValueKey('mini-player-play-pause'),
                                    tooltip: state.playing ? '暂停' : '播放',
                                    icon: Icon(
                                      state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.black,
                                      size: 26,
                                    ),
                                    onPressed: () => coordinator.togglePlayPause(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  key: const ValueKey('mini-player-seek-forward'),
                                  tooltip: '快进 10 秒',
                                  icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 24),
                                  onPressed: () => coordinator.seekRelative(const Duration(seconds: 10)),
                                ),
                              ],
                            ),
                          ),

                          // Bottom Progress Indicator
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: state.duration.inMilliseconds > 0
                                  ? (state.position.inMilliseconds / state.duration.inMilliseconds).clamp(0.0, 1.0)
                                  : 0.0,
                              backgroundColor: Colors.white12,
                              color: AppColors.spotlight,
                              minHeight: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
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
}
}
