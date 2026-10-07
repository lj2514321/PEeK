import 'dart:ui';

import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_border_beam.dart';
import 'package:embyplayer/src/core/presentation/peek_magnetic_button.dart';
import 'package:embyplayer/src/core/presentation/peek_spring.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:window_manager/window_manager.dart';


class PlaybackControls extends StatefulWidget {
  const PlaybackControls({
    super.key,
    required this.title,
    required this.method,
    required this.quality,
    required this.visible,
    required this.playing,
    required this.buffering,
    required this.changingSource,
    required this.sourceChangeLabel,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.volume,
    required this.rate,
    required this.fullScreen,
    required this.audioLabel,
    required this.subtitleLabel,
    required this.chapters,
    required this.queueAvailable,
    required this.canPrevious,
    required this.canNext,
    required this.onBack,
    required this.onPlayPause,
    required this.onSeekPreview,
    required this.onSeek,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onVolumeChanged,
    required this.onMute,
    required this.onRateChanged,
    required this.onAudio,
    required this.onSubtitle,
    required this.onChapters,
    required this.onPrevious,
    required this.onNext,
    required this.onEpisodes,
    required this.onDiagnostics,
    required this.onQuality,
    required this.onFullScreen,
    this.danmakuEnabled = true,
    this.onDanmaku,
    this.isPip = false,
    this.backTooltip,
    this.onPip,
    this.onAudioEnhancement,
    this.onOpenExternalPlayer,
    this.onClose,
    this.onMinimize,
    this.onToggleMaximize,
    this.onToggleAlwaysOnTop,
    this.isAlwaysOnTop = false,
    this.isMaximized = false,
  });

  final String title;
  final PlaybackMethod method;
  final PlaybackBitrate quality;
  final bool visible;
  final bool playing;
  final bool buffering;
  final bool changingSource;
  final String sourceChangeLabel;
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final double volume;
  final double rate;
  final bool fullScreen;
  final bool isPip;
  final String audioLabel;
  final String subtitleLabel;
  final List<MediaChapter> chapters;
  final bool queueAvailable;
  final bool canPrevious;
  final bool canNext;
  final String? backTooltip;
  final VoidCallback onBack;
  final VoidCallback? onClose;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onMute;
  final ValueChanged<double> onRateChanged;
  final VoidCallback onAudio;
  final VoidCallback onSubtitle;
  final VoidCallback onChapters;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onEpisodes;
  final VoidCallback onDiagnostics;
  final VoidCallback? onQuality;
  final VoidCallback onFullScreen;
  final bool danmakuEnabled;
  final VoidCallback? onDanmaku;
  final VoidCallback? onPip;
  final VoidCallback? onAudioEnhancement;
  final VoidCallback? onOpenExternalPlayer;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleMaximize;
  final VoidCallback? onToggleAlwaysOnTop;
  final bool isAlwaysOnTop;
  final bool isMaximized;

  @override
  State<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<PlaybackControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 160),
      value: widget.visible ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.16, 1.0, 0.3, 1.0),
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(PlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isTest) {
      return Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: !widget.visible,
            child: Opacity(
              opacity: widget.visible ? 1.0 : 0.0,
              child: _PlaybackTopBar(
                title: widget.title,
                method: widget.method,
                quality: widget.quality,
                changingSource: widget.changingSource,
                sourceChangeLabel: widget.sourceChangeLabel,
                backTooltip: widget.backTooltip,
                onBack: widget.onBack,
                onClose: widget.onClose,
                onDiagnostics: widget.onDiagnostics,
                onQuality: widget.onQuality,
                onAudioEnhancement: widget.onAudioEnhancement,
                onOpenExternalPlayer: widget.onOpenExternalPlayer,
                onFullScreen: widget.onFullScreen,
                onMinimize: widget.onMinimize,
                onToggleMaximize: widget.onToggleMaximize,
                onToggleAlwaysOnTop: widget.onToggleAlwaysOnTop,
                isAlwaysOnTop: widget.isAlwaysOnTop,
                isMaximized: widget.isMaximized,
              ),
            ),
          ),
          if (widget.buffering || widget.changingSource)
            Center(
              child: _BufferingIndicator(
                label: widget.changingSource
                    ? widget.sourceChangeLabel
                    : '正在缓冲',
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              ignoring: !widget.visible,
              child: Opacity(
                opacity: widget.visible ? 1.0 : 0.0,
                child: _PlaybackBottomBar(
                  playing: widget.playing,
                  position: widget.position,
                  duration: widget.duration,
                  buffer: widget.buffer,
                  volume: widget.volume,
                  rate: widget.rate,
                  fullScreen: widget.fullScreen,
                  audioLabel: widget.audioLabel,
                  subtitleLabel: widget.subtitleLabel,
                  chapters: widget.chapters,
                  queueAvailable: widget.queueAvailable,
                  canPrevious: widget.canPrevious,
                  canNext: widget.canNext,
                  onPlayPause: widget.onPlayPause,
                  onSeekPreview: widget.onSeekPreview,
                  onSeek: widget.onSeek,
                  onSeekBack: widget.onSeekBack,
                  onSeekForward: widget.onSeekForward,
                  onVolumeChanged: widget.onVolumeChanged,
                  onMute: widget.onMute,
                  onRateChanged: widget.onRateChanged,
                  onAudio: widget.onAudio,
                  onSubtitle: widget.onSubtitle,
                  onChapters: widget.onChapters,
                  onPrevious: widget.onPrevious,
                  onNext: widget.onNext,
                  onEpisodes: widget.onEpisodes,
                  onFullScreen: widget.onFullScreen,
                  danmakuEnabled: widget.danmakuEnabled,
                  onDanmaku: widget.onDanmaku,
                  isPip: widget.isPip,
                  onPip: widget.onPip,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final t = _animation.value;
        if (t <= 0.001 && !widget.visible) {
          if (widget.buffering || widget.changingSource) {
            return Center(
              child: _BufferingIndicator(
                label: widget.changingSource
                    ? widget.sourceChangeLabel
                    : '正在缓冲',
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final topOffsetY = -16.0 * (1.0 - t);
        final bottomOffsetY = 16.0 * (1.0 - t);
        final opacity = t.clamp(0.0, 1.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: !widget.visible,
              child: Transform.translate(
                offset: Offset(0, topOffsetY),
                child: Opacity(
                  opacity: opacity,
                  child: _PlaybackTopBar(
                    title: widget.title,
                    method: widget.method,
                    quality: widget.quality,
                    changingSource: widget.changingSource,
                    sourceChangeLabel: widget.sourceChangeLabel,
                    backTooltip: widget.backTooltip,
                    onBack: widget.onBack,
                    onClose: widget.onClose,
                    onDiagnostics: widget.onDiagnostics,
                    onQuality: widget.onQuality,
                    onAudioEnhancement: widget.onAudioEnhancement,
                    onOpenExternalPlayer: widget.onOpenExternalPlayer,
                    onFullScreen: widget.onFullScreen,
                    onMinimize: widget.onMinimize,
                    onToggleMaximize: widget.onToggleMaximize,
                    onToggleAlwaysOnTop: widget.onToggleAlwaysOnTop,
                    isAlwaysOnTop: widget.isAlwaysOnTop,
                    isMaximized: widget.isMaximized,
                  ),
                ),
              ),
            ),
            if (widget.buffering || widget.changingSource)
              Center(
                child: _BufferingIndicator(
                  label: widget.changingSource
                      ? widget.sourceChangeLabel
                      : '正在缓冲',
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: IgnorePointer(
                ignoring: !widget.visible,
                child: Transform.translate(
                  offset: Offset(0, bottomOffsetY),
                  child: Opacity(
                    opacity: opacity,
                    child: _PlaybackBottomBar(
                      playing: widget.playing,
                      position: widget.position,
                      duration: widget.duration,
                      buffer: widget.buffer,
                      volume: widget.volume,
                      rate: widget.rate,
                      fullScreen: widget.fullScreen,
                      audioLabel: widget.audioLabel,
                      subtitleLabel: widget.subtitleLabel,
                      chapters: widget.chapters,
                      queueAvailable: widget.queueAvailable,
                      canPrevious: widget.canPrevious,
                      canNext: widget.canNext,
                      onPlayPause: widget.onPlayPause,
                      onSeekPreview: widget.onSeekPreview,
                      onSeek: widget.onSeek,
                      onSeekBack: widget.onSeekBack,
                      onSeekForward: widget.onSeekForward,
                      onVolumeChanged: widget.onVolumeChanged,
                      onMute: widget.onMute,
                      onRateChanged: widget.onRateChanged,
                      onAudio: widget.onAudio,
                      onSubtitle: widget.onSubtitle,
                      onChapters: widget.onChapters,
                      onPrevious: widget.onPrevious,
                      onNext: widget.onNext,
                      onEpisodes: widget.onEpisodes,
                      onFullScreen: widget.onFullScreen,
                      danmakuEnabled: widget.danmakuEnabled,
                      onDanmaku: widget.onDanmaku,
                      isPip: widget.isPip,
                      onPip: widget.onPip,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaybackTopBar extends StatelessWidget {
  const _PlaybackTopBar({
    required this.title,
    required this.method,
    required this.quality,
    required this.changingSource,
    required this.sourceChangeLabel,
    required this.onBack,
    this.onClose,
    this.backTooltip,
    required this.onDiagnostics,
    required this.onQuality,
    this.onAudioEnhancement,
    this.onOpenExternalPlayer,
    required this.onFullScreen,
    this.onMinimize,
    this.onToggleMaximize,
    this.onToggleAlwaysOnTop,
    this.isAlwaysOnTop = false,
    this.isMaximized = false,
  });

  final String title;
  final PlaybackMethod method;
  final PlaybackBitrate quality;
  final bool changingSource;
  final String sourceChangeLabel;
  final String? backTooltip;
  final VoidCallback onBack;
  final VoidCallback? onClose;
  final VoidCallback onDiagnostics;
  final VoidCallback? onQuality;
  final VoidCallback? onAudioEnhancement;
  final VoidCallback? onOpenExternalPlayer;
  final VoidCallback onFullScreen;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleMaximize;
  final VoidCallback? onToggleAlwaysOnTop;
  final bool isAlwaysOnTop;
  final bool isMaximized;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: _PlaybackDragToMoveArea(
        onDoubleTap: onFullScreen,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC070810),
                Color(0x66070810),
                Colors.transparent,
              ],
              stops: [0.0, 0.65, 1.0],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 22, 38),
              child: Row(
                children: [
                  _ControlIconButton(
                    key: const ValueKey('player-back'),
                    tooltip: backTooltip ?? '缩小为悬浮画中画（Esc）',
                    icon: Icons.arrow_back_rounded,
                    onPressed: onBack,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          changingSource
                              ? sourceChangeLabel
                              : 'PEeK PRIVATE CINEMA',
                          style: const TextStyle(
                            color: Color(0xFFB7BBC4),
                            fontFamily: 'Cascadia Mono',
                            fontSize: 9,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (onAudioEnhancement != null) ...[
                    _ControlIconButton(
                      key: const ValueKey('player-audio-enhancement'),
                      tooltip: '音画增强与夜间模式',
                      icon: Icons.graphic_eq_rounded,
                      onPressed: onAudioEnhancement!,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (onOpenExternalPlayer != null) ...[
                    _ControlIconButton(
                      key: const ValueKey('player-open-external'),
                      tooltip: '在外部播放器（PotPlayer）中打开',
                      icon: Icons.open_in_new_rounded,
                      onPressed: onOpenExternalPlayer!,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _ControlIconButton(
                    key: const ValueKey('player-diagnostics'),
                    tooltip: '播放诊断（Ctrl+D）',
                    icon: Icons.monitor_heart_outlined,
                    onPressed: onDiagnostics,
                  ),
                  if (onQuality != null)
                    _MethodBadge(
                      method: method,
                      quality: quality,
                      onPressed: changingSource ? null : onQuality,
                    )
                  else
                    const _LocalSourceBadge(),
                  if (onToggleAlwaysOnTop != null) ...[
                    const SizedBox(width: 8),
                    _ControlIconButton(
                      key: const ValueKey('player-pin'),
                      tooltip: isAlwaysOnTop ? '取消置顶' : '置顶窗口',
                      icon: isAlwaysOnTop
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      onPressed: onToggleAlwaysOnTop!,
                    ),
                  ],
                  if (onMinimize != null) ...[
                    const SizedBox(width: 8),
                    _ControlIconButton(
                      key: const ValueKey('player-minimize'),
                      tooltip: '最小化',
                      icon: Icons.remove_rounded,
                      onPressed: onMinimize!,
                    ),
                  ],
                  if (onToggleMaximize != null) ...[
                    const SizedBox(width: 8),
                    _ControlIconButton(
                      key: const ValueKey('player-maximize'),
                      tooltip: isMaximized ? '向下还原' : '最大化',
                      icon: isMaximized
                          ? Icons.crop_portrait_rounded
                          : Icons.crop_square_rounded,
                      onPressed: onToggleMaximize!,
                    ),
                  ],
                  if (onClose != null) ...[
                    const SizedBox(width: 8),
                    _ControlIconButton(
                      key: const ValueKey('player-close'),
                      tooltip: '退出播放',
                      icon: Icons.close_rounded,
                      onPressed: onClose,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackDragToMoveArea extends StatelessWidget {
  const _PlaybackDragToMoveArea({
    required this.child,
    required this.onDoubleTap,
  });

  final Widget child;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        windowManager.startDragging();
      },
      onDoubleTap: onDoubleTap,
      child: child,
    );
  }
}

class _LocalSourceBadge extends StatelessWidget {
  const _LocalSourceBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('player-local-source'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1.0,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage_rounded, size: 14),
          SizedBox(width: 6),
          Text('本地直放', style: TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _PlaybackBottomBar extends StatelessWidget {
  const _PlaybackBottomBar({
    required this.playing,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.volume,
    required this.rate,
    required this.fullScreen,
    required this.audioLabel,
    required this.subtitleLabel,
    required this.chapters,
    required this.queueAvailable,
    required this.canPrevious,
    required this.canNext,
    required this.onPlayPause,
    required this.onSeekPreview,
    required this.onSeek,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onVolumeChanged,
    required this.onMute,
    required this.onRateChanged,
    required this.onAudio,
    required this.onSubtitle,
    required this.onChapters,
    required this.onPrevious,
    required this.onNext,
    required this.onEpisodes,
    required this.onFullScreen,
    this.danmakuEnabled = true,
    this.onDanmaku,
    this.isPip = false,
    this.onPip,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final double volume;
  final double rate;
  final bool fullScreen;
  final bool isPip;
  final bool danmakuEnabled;
  final VoidCallback? onDanmaku;
  final String audioLabel;
  final String subtitleLabel;
  final List<MediaChapter> chapters;
  final bool queueAvailable;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onMute;
  final ValueChanged<double> onRateChanged;
  final VoidCallback onAudio;
  final VoidCallback onSubtitle;
  final VoidCallback onChapters;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onEpisodes;
  final VoidCallback onFullScreen;
  final VoidCallback? onPip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final veryCompact = constraints.maxWidth < 470;
        final showQueueTransport =
            queueAvailable && constraints.maxWidth >= 940;
        final padding = compact
            ? const EdgeInsets.fromLTRB(10, 0, 10, 10)
            : const EdgeInsets.fromLTRB(22, 0, 22, 20);
        final radius = compact ? 22.0 : 28.0;
        return Padding(
          padding: padding,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: compact ? double.infinity : 960,
              ),
              child: Container(
                decoration: AppGlass.visionOSDecoration(
                  radius: radius,
                  elevated: false,
                  glowColor: const Color(0x284A90E2),
                  borderOpacity: 0.28,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 18,
                        compact ? 4 : 6,
                        compact ? 12 : 18,
                        compact ? 8 : 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (chapters.isNotEmpty)
                            _ChapterRail(
                              chapters: chapters,
                              position: position,
                              onPressed: onChapters,
                            ),
                          _Timeline(
                            position: position,
                            duration: duration,
                            buffer: buffer,
                            chapters: chapters,
                            onSeekPreview: onSeekPreview,
                            onSeek: onSeek,
                          ),
                          Row(
                            children: [
                              _ControlIconButton(
                                key: const ValueKey('player-play-pause'),
                                tooltip: playing ? '暂停（Space）' : '播放（Space）',
                                icon: playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                prominent: true,
                                onPressed: onPlayPause,
                              ),
                              if (!compact) ...[
                                const SizedBox(width: 2),
                                _ControlIconButton(
                                  tooltip: '后退 10 秒（←）',
                                  icon: Icons.replay_10_rounded,
                                  onPressed: onSeekBack,
                                ),
                                _ControlIconButton(
                                  tooltip: '前进 10 秒（→）',
                                  icon: Icons.forward_10_rounded,
                                  onPressed: onSeekForward,
                                ),
                              ],
                              if (showQueueTransport) ...[
                                _ControlIconButton(
                                  key: const ValueKey('player-previous'),
                                  tooltip: '上一集（P）',
                                  icon: Icons.skip_previous_rounded,
                                  onPressed: canPrevious ? onPrevious : null,
                                ),
                                _ControlIconButton(
                                  key: const ValueKey('player-episodes'),
                                  tooltip: '选集',
                                  icon: Icons.video_collection_rounded,
                                  onPressed: onEpisodes,
                                ),
                                _ControlIconButton(
                                  key: const ValueKey('player-next'),
                                  tooltip: '下一集（N）',
                                  icon: Icons.skip_next_rounded,
                                  onPressed: canNext ? onNext : null,
                                ),
                              ] else if (queueAvailable)
                                _ControlIconButton(
                                  key: const ValueKey('player-episodes'),
                                  tooltip: '选集',
                                  icon: Icons.video_collection_rounded,
                                  onPressed: onEpisodes,
                                ),
                              const SizedBox(width: 4),
                              Text(
                                veryCompact
                                    ? _time(position)
                                    : '${_time(position)} / ${_time(duration)}',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cascadia Mono',
                                  fontSize: veryCompact ? 9 : 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              if (!compact) ...[
                                _ControlIconButton(
                                  tooltip: volume <= 0 ? '取消静音（M）' : '静音（M）',
                                  icon: _volumeIcon(volume),
                                  onPressed: onMute,
                                ),
                                SizedBox(
                                  key: const ValueKey('player-volume'),
                                  width: 92,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: AppColors.textSecondary,
                                      inactiveTrackColor: Colors.white
                                          .withValues(alpha: 0.14),
                                      thumbColor: Colors.white,
                                      overlayColor: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      trackHeight: 2.5,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 4.5,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 10,
                                          ),
                                    ),
                                    child: Slider(
                                      value: volume.clamp(0, 100),
                                      min: 0,
                                      max: 100,
                                      onChanged: onVolumeChanged,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              _ControlIconButton(
                                key: const ValueKey('player-audio'),
                                tooltip: '音轨：$audioLabel',
                                icon: Icons.graphic_eq_rounded,
                                onPressed: onAudio,
                              ),
                              _ControlIconButton(
                                key: const ValueKey('player-subtitle'),
                                tooltip: '字幕：$subtitleLabel',
                                icon: subtitleLabel == '关闭'
                                    ? Icons.subtitles_off_rounded
                                    : Icons.subtitles_rounded,
                                onPressed: onSubtitle,
                              ),
                              if (onDanmaku != null)
                                _ControlIconButton(
                                  key: const ValueKey('player-danmaku'),
                                  tooltip: danmakuEnabled ? '弹幕设置' : '弹幕（已关闭）',
                                  icon: danmakuEnabled
                                      ? Icons.comment_rounded
                                      : Icons.comments_disabled_rounded,
                                  onPressed: onDanmaku,
                                ),
                              if (!veryCompact)
                                _RateButton(
                                  rate: rate,
                                  onChanged: onRateChanged,
                                ),
                              if (onPip != null)
                                _ControlIconButton(
                                  key: const ValueKey('player-pip'),
                                  tooltip: isPip ? '退出置顶小窗' : '画中画置顶小窗',
                                  icon: isPip
                                      ? Icons.picture_in_picture_alt_rounded
                                      : Icons.picture_in_picture_rounded,
                                  onPressed: onPip,
                                ),
                              _ControlIconButton(
                                key: const ValueKey('player-fullscreen'),
                                tooltip: fullScreen ? '退出全屏（F）' : '全屏（F）',
                                icon: fullScreen
                                    ? Icons.fullscreen_exit_rounded
                                    : Icons.fullscreen_rounded,
                                onPressed: onFullScreen,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.position,
    required this.duration,
    required this.buffer,
    required this.chapters,
    required this.onSeekPreview,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final Duration buffer;
  final List<MediaChapter> chapters;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final maximum = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final value = position.inMilliseconds.clamp(0, maximum.toInt()).toDouble();
    final buffered = buffer.inMilliseconds
        .clamp(value.toInt(), maximum.toInt())
        .toDouble();
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.spotlight,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.13),
                secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.28),
                thumbColor: AppColors.spotlight,
                overlayColor: AppColors.spotlight.withValues(alpha: 0.14),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                key: const ValueKey('player-seek'),
                value: value,
                secondaryTrackValue: buffered,
                max: maximum,
                onChanged: (value) {
                  onSeekPreview(Duration(milliseconds: value.round()));
                },
                onChangeEnd: (value) {
                  onSeek(Duration(milliseconds: value.round()));
                },
              ),
            ),
          ),
          if (duration > Duration.zero)
            Positioned(
              left: 24,
              right: 24,
              top: 20,
              height: 8,
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final usableChapters = chapters
                        .where(
                          (chapter) =>
                              chapter.startPosition > Duration.zero &&
                              chapter.startPosition < duration,
                        )
                        .toList(growable: false);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (
                          var index = 0;
                          index < usableChapters.length;
                          index++
                        )
                          Positioned(
                            key: ValueKey('chapter-marker-$index'),
                            left:
                                (usableChapters[index]
                                            .startPosition
                                            .inMilliseconds /
                                        duration.inMilliseconds) *
                                    constraints.maxWidth -
                                1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color:
                                    usableChapters[index].startPosition <=
                                        position
                                    ? AppColors.spotlight
                                    : Colors.white.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x66000000),
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                              child: const SizedBox(width: 2, height: 8),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterRail extends StatelessWidget {
  const _ChapterRail({
    required this.chapters,
    required this.position,
    required this.onPressed,
  });

  final List<MediaChapter> chapters;
  final Duration position;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    var currentIndex = 0;
    for (var index = 0; index < chapters.length; index++) {
      if (chapters[index].startPosition <= position) currentIndex = index;
    }
    final chapter = chapters[currentIndex];
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('player-chapters'),
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bookmarks_rounded,
                  size: 14,
                  color: AppColors.spotlight,
                ),
                const SizedBox(width: 7),
                Text(
                  'CH ${(currentIndex + 1).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: AppColors.spotlight,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    chapter.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlIconButton extends StatelessWidget {
  const _ControlIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.prominent = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final Widget button;
    if (prominent) {
      button = Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.spotlight.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            foregroundColor: AppColors.onSpotlight,
            backgroundColor: AppColors.spotlight,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            elevation: 8,
            padding: const EdgeInsets.all(9),
          ),
          icon: Icon(icon, size: 24),
        ),
      );
    } else {
      button = IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          hoverColor: Colors.white.withValues(alpha: 0.12),
          focusColor: AppColors.spotlight.withValues(alpha: 0.2),
        ),
        icon: Icon(icon, size: 20),
      );
    }

    return PeekMagneticButton(
      enabled: onPressed != null,
      maxOffset: prominent ? 5.0 : 3.5,
      pressScale: prominent ? 0.92 : 0.94,
      hoverScale: prominent ? 1.05 : 1.04,
      child: button,
    );
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton({required this.rate, required this.onChanged});

  final double rate;
  final ValueChanged<double> onChanged;

  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      key: const ValueKey('player-rate'),
      tooltip: '播放速度',
      initialValue: rate,
      onSelected: onChanged,
      color: AppColors.surfaceHigh,
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      itemBuilder: (context) => [
        for (final value in _rates)
          PopupMenuItem(
            value: value,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: value == rate
                      ? const Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: AppColors.spotlight,
                        )
                      : null,
                ),
                Text('${value}x'),
              ],
            ),
          ),
      ],
      child: PeekMagneticButton(
        maxOffset: 3.0,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 0.8,
            ),
          ),
          child: Text(
            '${rate}x',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Cascadia Mono',
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({
    required this.method,
    required this.quality,
    required this.onPressed,
  });

  final PlaybackMethod method;
  final PlaybackBitrate quality;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final methodLabel = switch (method) {
      PlaybackMethod.directPlay => 'DIRECT PLAY',
      PlaybackMethod.directStream => 'DIRECT STREAM',
      PlaybackMethod.transcode => 'TRANSCODE',
    };
    final showMethod = MediaQuery.sizeOf(context).width >= 560;
    return Tooltip(
      message: '画质上限：${quality.label}',
      child: PeekMagneticButton(
        enabled: onPressed != null,
        maxOffset: 3.0,
        child: Material(
          color: Colors.black.withValues(alpha: 0.42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1.0,
            ),
          ),
          child: InkWell(
            key: const ValueKey('player-quality'),
            borderRadius: BorderRadius.circular(99),
            onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 6, 9, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showMethod) ...[
                  Text(
                    methodLabel,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 9,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 11,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ],
                Text(
                  quality.compactLabel,
                  style: const TextStyle(
                    color: AppColors.spotlight,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}

class _BufferingIndicator extends StatelessWidget {
  const _BufferingIndicator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 16,
      blur: 18,
      tint: const Color(0xAA0D1018),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}

class PlaybackSeekFeedback extends StatelessWidget {
  const PlaybackSeekFeedback({
    super.key,
    required this.deltaSeconds,
    required this.position,
  });

  final int deltaSeconds;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final forward = deltaSeconds >= 0;
    final seconds = deltaSeconds.abs();
    final label = '${forward ? '快进' : '快退'} $seconds 秒';
    final themeColor = forward ? AppColors.spotlight : AppColors.cyan;

    final indicator = Semantics(
      liveRegion: true,
      label: '$label，当前位置 ${_time(position)}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.04),
                  Colors.black.withValues(alpha: 0.38),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.22),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  forward ? Icons.forward_10_rounded : Icons.replay_10_rounded,
                  color: themeColor,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                Container(
                  width: 3,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  _time(position),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontFamily: 'Cascadia Mono',
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (AppMotion.isTest) return indicator;
    final beamed = PeekBorderBeam(
      borderRadius: BorderRadius.circular(20),
      beamColor: themeColor,
      secondaryColor: forward ? AppColors.spotlightLight : AppColors.cyanLight,
      duration: const Duration(seconds: 3),
      child: indicator,
    );
    return beamed
        .animate()
        .fadeIn(duration: const Duration(milliseconds: 140))
        .slideY(
          begin: -0.12,
          end: 0,
          duration: const Duration(milliseconds: 160),
          curve: PeekCurves.spatialEnter,
        );
  }
}

class NextEpisodeCountdown extends StatelessWidget {
  const NextEpisodeCountdown({
    super.key,
    required this.item,
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.onPlayNow,
    required this.onCancel,
  });

  final MediaItem item;
  final int secondsRemaining;
  final int totalSeconds;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final progress = totalSeconds <= 0
        ? 0.0
        : (secondsRemaining / totalSeconds).clamp(0.0, 1.0);
    return SafeArea(
      minimum: const EdgeInsets.all(18),
      child: Center(
        child: GlassSurface(
          radius: 24,
          blur: 28,
          tint: const Color(0xE80D1018),
          elevated: true,
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 66,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        key: const ValueKey('next-episode-progress'),
                        value: progress,
                        strokeWidth: 4,
                        color: AppColors.spotlight,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                      ),
                      Center(
                        child: Text(
                          '$secondsRemaining',
                          style: const TextStyle(
                            color: AppColors.spotlight,
                            fontFamily: 'Cascadia Mono',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text('即将播放下一集', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 7),
                Text(
                  _episodeTitle(item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('next-episode-cancel'),
                      onPressed: onCancel,
                      child: const Text('取消连播'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('next-episode-play-now'),
                      onPressed: onPlayNow,
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('立即播放'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _episodeTitle(MediaItem item) {
  final season = item.parentIndexNumber;
  final episode = item.indexNumber;
  final prefix = season == null && episode == null
      ? ''
      : 'S${(season ?? 0).toString().padLeft(2, '0')}'
            'E${(episode ?? 0).toString().padLeft(2, '0')} · ';
  return '$prefix${item.name}';
}

IconData _volumeIcon(double volume) {
  if (volume <= 0) return Icons.volume_off_rounded;
  if (volume < 45) return Icons.volume_down_rounded;
  return Icons.volume_up_rounded;
}

String _time(Duration value) {
  final totalSeconds = value.inSeconds < 0 ? 0 : value.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
