import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:flutter/material.dart';

class PlaybackQualitySheet extends StatelessWidget {
  const PlaybackQualitySheet({super.key, required this.selected});

  final PlaybackBitrate selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassSurface(
            radius: 24,
            blur: 28,
            tint: AppColors.glassStrong,
            elevated: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: MediaQuery.sizeOf(context).height * 0.86,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 14, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.spotlight.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.high_quality_rounded,
                            color: AppColors.spotlight,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '播放画质',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '当前上限 · ${selected.label}',
                                style: const TextStyle(
                                  color: AppColors.textTertiary,
                                  fontFamily: 'Cascadia Mono',
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: PeekSmoothScroll(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        children: [
                          for (final bitrate in PlaybackBitrate.values)
                            _QualityOption(
                              bitrate: bitrate,
                              selected: bitrate == selected,
                              onPressed: () =>
                                  Navigator.of(context).pop(bitrate),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: AppColors.textTertiary,
                        ),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '较低上限可能触发服务器转码；部分外部 STRM 流仍由源站决定实际画质。',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                              height: 1.45,
                            ),
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
    );
  }
}

class _QualityOption extends StatelessWidget {
  const _QualityOption({
    required this.bitrate,
    required this.selected,
    required this.onPressed,
  });

  final PlaybackBitrate bitrate;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.glassSelected : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('quality-option-${bitrate.name}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppColors.spotlight,
                        size: 20,
                      )
                    : Text(
                        bitrate.compactLabel,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontFamily: 'Cascadia Mono',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bitrate.label,
                      style: TextStyle(
                        color: selected ? Colors.white : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _description(bitrate),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                bitrate == PlaybackBitrate.original
                    ? 'MAX'
                    : bitrate.detail.toUpperCase(),
                style: TextStyle(
                  color: selected
                      ? AppColors.spotlight
                      : AppColors.textTertiary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _description(PlaybackBitrate bitrate) {
    return switch (bitrate) {
      PlaybackBitrate.original => '优先保持片源原始码率，适合稳定局域网',
      PlaybackBitrate.mbps120 => '高码率 4K 与原盘片源',
      PlaybackBitrate.mbps80 => '大多数 4K 片源',
      PlaybackBitrate.mbps40 => '4K 或高码率 1080p',
      PlaybackBitrate.mbps20 => '远程播放的画质与带宽平衡',
      PlaybackBitrate.mbps10 => '普通宽带与移动网络',
      PlaybackBitrate.mbps5 => '弱网环境或节省流量',
    };
  }
}
