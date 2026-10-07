import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/player/presentation/global_playback_coordinator.dart';
import 'package:embyplayer/src/features/player/presentation/player_window_coordinator.dart';
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

    if (state.mode == PlaybackPresentationMode.window && state.item != null) {
      return _buildWindowPlaybackIndicator(context, state);
    }

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
              decoration: AppGlass.visionOSDecoration(
                radius: 18,
                elevated: true,
                glowColor: const Color(0x354A90E2),
                borderOpacity: 0.30,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
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

  Widget _buildWindowPlaybackIndicator(
    BuildContext context,
    GlobalPlaybackState state,
  ) {
    final padding = MediaQuery.of(context).padding;
    const indicatorWidth = 320.0;
    const indicatorHeight = 62.0;

    final right = 24.0;
    final bottom = 24.0 + padding.bottom;

    return Positioned(
      right: right,
      bottom: bottom,
      width: indicatorWidth,
      height: indicatorHeight,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: AppGlass.visionOSDecoration(
            radius: 14,
            elevated: true,
            glowColor: AppColors.spotlight.withValues(alpha: 0.15),
            borderOpacity: 0.28,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                InkWell(
                  onTap: () =>
                      ref.read(playerWindowCoordinatorProvider).focusWindow(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.smart_display_rounded,
                            color: AppColors.spotlight,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppColors.spotlight,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    '正在独立窗口播放',
                                    style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                state.item!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '唤起播放窗口',
                          icon: const Icon(
                            Icons.open_in_new_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () => ref
                              .read(playerWindowCoordinatorProvider)
                              .focusWindow(),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '关闭播放',
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                          onPressed: () => ref
                              .read(playerWindowCoordinatorProvider)
                              .closeWindow(),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: state.duration.inMilliseconds > 0
                        ? (state.position.inMilliseconds /
                                state.duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0,
                    backgroundColor: Colors.white10,
                    color: AppColors.spotlight,
                    minHeight: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
