import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/player/domain/playback_diagnostics.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:flutter/material.dart';

class PlaybackDiagnosticsPanel extends StatelessWidget {
  const PlaybackDiagnosticsPanel({
    super.key,
    required this.snapshot,
    required this.loading,
    required this.onCopy,
    required this.onRefresh,
    required this.onClose,
  });

  final PlaybackDiagnosticsSnapshot? snapshot;
  final bool loading;
  final VoidCallback onCopy;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    return Semantics(
      container: true,
      label: '播放诊断面板',
      child: GlassSurface(
        key: const ValueKey('playback-diagnostics-panel'),
        radius: 20,
        blur: 28,
        tint: const Color(0xED111520),
        elevated: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DiagnosticsHeader(
              data: data,
              loading: loading,
              onCopy: data == null ? null : onCopy,
              onRefresh: loading ? null : onRefresh,
              onClose: onClose,
            ),
            Flexible(
              child: data == null
                  ? const _DiagnosticsLoading()
                  : PeekSmoothScroll(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SectionLabel(label: '播放路径'),
                            const SizedBox(height: 8),
                            _DiagnosticsGrid(
                              items: [
                                _DiagnosticValue('播放方式', data.methodLabel),
                                _DiagnosticValue('实际解码', data.decoderLabel),
                                _DiagnosticValue(
                                  '传输协议',
                                  data.sourceProtocol.toUpperCase(),
                                ),
                                _DiagnosticValue(
                                  '解码偏好',
                                  data.requestedDecodingMode.label,
                                ),
                              ],
                            ),
                            if (data.method == PlaybackMethod.transcode) ...[
                              const SizedBox(height: 10),
                              _TranscodingReasons(
                                reasons: data.transcodingReasons,
                              ),
                            ],
                            const SizedBox(height: 18),
                            _SectionLabel(label: '媒体信息'),
                            const SizedBox(height: 8),
                            _DiagnosticsGrid(
                              items: [
                                _DiagnosticValue(
                                  '视频编码',
                                  _available(data.videoCodec),
                                ),
                                _DiagnosticValue(
                                  '音频编码',
                                  _available(data.audioCodec),
                                ),
                                _DiagnosticValue('分辨率', data.resolutionLabel),
                                _DiagnosticValue('帧率', data.frameRateLabel),
                                _DiagnosticValue(
                                  '封装格式',
                                  _available(data.container),
                                ),
                                _DiagnosticValue('色彩信息', data.colorLabel),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _SectionLabel(label: '实时状态'),
                            const SizedBox(height: 8),
                            _DiagnosticsGrid(
                              items: [
                                _DiagnosticValue(
                                  '视频码率',
                                  data.videoBitrateLabel,
                                ),
                                _DiagnosticValue(
                                  '音频码率',
                                  data.audioBitrateLabel,
                                ),
                                _DiagnosticValue(
                                  data.buffering ? '缓存 · 正在缓冲' : '缓存',
                                  data.cacheLabel,
                                ),
                                _DiagnosticValue('丢帧', data.droppedFramesLabel),
                                _DiagnosticValue(
                                  '视频输出',
                                  _available(data.videoOutput),
                                ),
                                _DiagnosticValue('采样时间', _time(data.sampledAt)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.privacy_tip_outlined,
                                  size: 17,
                                  color: AppColors.textTertiary,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '复制内容不会包含媒体地址、Token、用户或媒体标识。',
                                    style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 12,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _available(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? '不可用' : text.toUpperCase();
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _DiagnosticsHeader extends StatelessWidget {
  const _DiagnosticsHeader({
    required this.data,
    required this.loading,
    required this.onCopy,
    required this.onRefresh,
    required this.onClose,
  });

  final PlaybackDiagnosticsSnapshot? data;
  final bool loading;
  final VoidCallback? onCopy;
  final VoidCallback? onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.indigo.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.monitor_heart_outlined,
              color: AppColors.indigo,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PLAYBACK DIAGNOSTICS',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.indigo,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data?.decoderLabel ?? '正在读取播放器状态',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            key: const ValueKey('diagnostics-refresh'),
            tooltip: '刷新诊断信息',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            key: const ValueKey('diagnostics-copy'),
            tooltip: '复制脱敏诊断信息',
            onPressed: onCopy,
            icon: const Icon(Icons.content_copy_rounded),
          ),
          IconButton(
            key: const ValueKey('diagnostics-close'),
            tooltip: '关闭诊断面板（Esc）',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsLoading extends StatelessWidget {
  const _DiagnosticsLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 16),
            Text(
              '正在读取 libmpv 实时属性…',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DiagnosticsGrid extends StatelessWidget {
  const _DiagnosticsGrid({required this.items});

  final List<_DiagnosticValue> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 360 ? 2 : 1;
        const gap = 8.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _DiagnosticCell(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _DiagnosticValue {
  const _DiagnosticValue(this.label, this.value);

  final String label;
  final String value;
}

class _DiagnosticCell extends StatelessWidget {
  const _DiagnosticCell({required this.item});

  final _DiagnosticValue item;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.label,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
          ),
          const SizedBox(height: 5),
          Text(
            item.value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Cascadia Mono',
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscodingReasons extends StatelessWidget {
  const _TranscodingReasons({required this.reasons});

  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final labels = reasons.isEmpty
        ? const ['服务器未提供具体转码原因']
        : reasons.map(_reasonLabel).toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.spotlight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppColors.spotlight,
              ),
              SizedBox(width: 7),
              Text(
                '转码原因',
                style: TextStyle(
                  color: AppColors.spotlight,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final label in labels)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $label',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _reasonLabel(String value) {
    return switch (value) {
      'ContainerNotSupported' => '封装格式不支持直接播放',
      'VideoCodecNotSupported' => '视频编码不受支持',
      'AudioCodecNotSupported' => '音频编码不受支持',
      'SubtitleCodecNotSupported' => '字幕格式需要转换',
      'AudioChannelsNotSupported' => '音频声道布局不受支持',
      'VideoResolutionNotSupported' => '视频分辨率超出设备能力',
      'VideoBitrateNotSupported' ||
      'ContainerBitrateExceedsLimit' => '视频码率超过当前上限',
      'VideoBitDepthNotSupported' => '视频位深不受支持',
      'RefFramesNotSupported' => '视频参考帧参数不受支持',
      'DirectPlayError' => '服务器直接播放检查失败',
      _ => value,
    };
  }
}
