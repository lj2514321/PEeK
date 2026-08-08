import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class PlaybackControls extends StatelessWidget {
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
    this.isPip = false,
    this.onPip,
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
  final VoidCallback onBack;
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
  final VoidCallback? onPip;

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.responsive(
      context,
      visible ? AppMotion.fast : const Duration(milliseconds: 130),
    );
    final curve = visible ? Curves.easeOutCubic : Curves.easeInCubic;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: motion,
            curve: curve,
            child: _PlaybackTopBar(
              title: title,
              method: method,
              quality: quality,
              changingSource: changingSource,
              sourceChangeLabel: sourceChangeLabel,
              onBack: onBack,
              onDiagnostics: onDiagnostics,
              onQuality: onQuality,
            ),
          ),
        ),
        if (buffering || changingSource)
          Center(
            child: _BufferingIndicator(
              label: changingSource ? sourceChangeLabel : '正在缓冲',
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.08),
              duration: motion,
              curve: curve,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: motion,
                curve: curve,
                child: _PlaybackBottomBar(
                  playing: playing,
                  position: position,
                  duration: duration,
                  buffer: buffer,
                  volume: volume,
                  rate: rate,
                  fullScreen: fullScreen,
                  audioLabel: audioLabel,
                  subtitleLabel: subtitleLabel,
                  chapters: chapters,
                  queueAvailable: queueAvailable,
                  canPrevious: canPrevious,
                  canNext: canNext,
                  onPlayPause: onPlayPause,
                  onSeekPreview: onSeekPreview,
                  onSeek: onSeek,
                  onSeekBack: onSeekBack,
                  onSeekForward: onSeekForward,
                  onVolumeChanged: onVolumeChanged,
                  onMute: onMute,
                  onRateChanged: onRateChanged,
                  onAudio: onAudio,
                  onSubtitle: onSubtitle,
                  onChapters: onChapters,
                  onPrevious: onPrevious,
                  onNext: onNext,
                  onEpisodes: onEpisodes,
                  onFullScreen: onFullScreen,
                  isPip: isPip,
                  onPip: onPip,
                ),
              ),
            ),
          ),
        ),
      ],
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
    required this.onDiagnostics,
    required this.onQuality,
  });

  final String title;
  final PlaybackMethod method;
  final PlaybackBitrate quality;
  final bool changingSource;
  final String sourceChangeLabel;
  final VoidCallback onBack;
  final VoidCallback onDiagnostics;
  final VoidCallback? onQuality;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: DragToMoveArea(
        child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xD9000000), Color(0x66000000), Colors.transparent],
            stops: [0, 0.58, 1],
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
                  tooltip: '退出播放（Esc）',
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
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _LocalSourceBadge extends StatelessWidget {
  const _LocalSourceBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('player-local-source'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage_rounded, size: 15),
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
            : const EdgeInsets.fromLTRB(22, 0, 22, 18);
        return Padding(
          padding: padding,
          child: GlassSurface(
            radius: compact ? 16 : 20,
            blur: 0,
            tint: const Color(0xB80D1018),
            elevated: true,
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : 14,
              4,
              compact ? 8 : 14,
              compact ? 7 : 10,
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
                        fontSize: veryCompact ? 9 : 10,
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
                        child: Slider(
                          value: volume.clamp(0, 100),
                          min: 0,
                          max: 100,
                          onChanged: onVolumeChanged,
                        ),
                      ),
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
                    if (!veryCompact)
                      _RateButton(rate: rate, onChanged: onRateChanged),
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
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      style: prominent
          ? IconButton.styleFrom(
              foregroundColor: AppColors.onSpotlight,
              backgroundColor: AppColors.spotlight,
            )
          : null,
      icon: Icon(icon, size: prominent ? 25 : 21),
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
      child: SizedBox(
        width: 46,
        height: 44,
        child: Center(
          child: Text(
            '${rate}x',
            style: const TextStyle(
              color: AppColors.textSecondary,
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
      child: Material(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          key: const ValueKey('player-quality'),
          borderRadius: BorderRadius.circular(99),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
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
                      letterSpacing: 0.5,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 11,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: Colors.white.withValues(alpha: 0.14),
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
    return Semantics(
      liveRegion: true,
      label: '$label，当前位置 ${_time(position)}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xE60D1018),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                forward ? Icons.forward_10_rounded : Icons.replay_10_rounded,
                color: AppColors.spotlight,
                size: 30,
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _time(position),
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
