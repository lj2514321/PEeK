import 'dart:io';

import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/player/data/external_player_service.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

class PlaybackSettingsSection extends StatelessWidget {
  const PlaybackSettingsSection({
    super.key,
    required this.settings,
    required this.loading,
    required this.saving,
    required this.onBitrateChanged,
    required this.onHardwareDecodingModeChanged,
    this.onEnableMiniPlayerChanged,
    this.onUseExternalPlayerChanged,
    this.onExternalPlayerPathChanged,
    this.error,
  });

  final PlaybackSettings settings;
  final bool loading;
  final bool saving;
  final String? error;
  final ValueChanged<PlaybackBitrate>? onBitrateChanged;
  final ValueChanged<HardwareDecodingMode>? onHardwareDecodingModeChanged;
  final ValueChanged<bool>? onEnableMiniPlayerChanged;
  final ValueChanged<bool>? onUseExternalPlayerChanged;
  final ValueChanged<String?>? onExternalPlayerPathChanged;

  @override
  Widget build(BuildContext context) {
    final bitrateEnabled = !loading && !saving && onBitrateChanged != null;
    final hardwareDecodingEnabled =
        !loading && !saving && onHardwareDecodingModeChanged != null;
    return Container(
      key: const ValueKey('playback-settings-section'),
      padding: const EdgeInsets.all(24),
      decoration: AppGlass.decoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHeader(loading: loading, saving: saving, error: error),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 820
                  ? 4
                  : constraints.maxWidth >= 500
                  ? 3
                  : 2;
              const gap = 12.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final bitrate in PlaybackBitrate.values)
                    SizedBox(
                      width: width,
                      child: _BitrateOption(
                        bitrate: bitrate,
                        selected: settings.maxStreamingBitrate == bitrate,
                        enabled: bitrateEnabled,
                        onSelected: () => onBitrateChanged?.call(bitrate),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Text('解码方式', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            '自动模式优先使用安全的硬件解码；遇到不支持的格式时会回退到软件解码。',
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 2 : 1;
              const gap = 12.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final mode in HardwareDecodingMode.values)
                    SizedBox(
                      width: width,
                      child: _HardwareDecodingOption(
                        mode: mode,
                        selected: settings.hardwareDecodingMode == mode,
                        enabled: hardwareDecodingEnabled,
                        onSelected: () =>
                            onHardwareDecodingModeChanged?.call(mode),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Text('悬浮画中画（迷你小窗）', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            '全屏播放时点击返回或按 Esc，自动缩小为悬浮小窗继续播放，支持随意拖拽与边看边找片。',
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: settings.enableMiniPlayer
                  ? AppColors.indigo.withValues(alpha: 0.11)
                  : AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: settings.enableMiniPlayer
                    ? AppColors.indigo.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.picture_in_picture_alt_rounded,
                  color: settings.enableMiniPlayer
                      ? AppColors.indigo
                      : AppColors.textTertiary,
                  size: 24,
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '开启应用内悬浮迷你播放器',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '关闭后，返回将直接退出并停止播放，不再缩小为小窗',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  key: const ValueKey('setting-enable-mini-player'),
                  value: settings.enableMiniPlayer,
                  activeTrackColor: AppColors.indigo,
                  onChanged: (!loading && !saving && onEnableMiniPlayerChanged != null)
                      ? onEnableMiniPlayerChanged
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('外部播放器（如 PotPlayer / VLC）', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            '调用系统外部独立播放器播放视频流，支持 PotPlayer、VLC 等，享受自定义渲染器（如 MadVR）或独立窗口多屏播放。',
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 14),
          _ExternalPlayerConfigCard(
            settings: settings,
            loading: loading,
            saving: saving,
            onUseExternalPlayerChanged: onUseExternalPlayerChanged,
            onExternalPlayerPathChanged: onExternalPlayerPathChanged,
          ),
          const SizedBox(height: 16),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  '码率限制会在下一次开始播放或重新选择音轨时生效，不会中断当前影片。'
                  '较低码率可能触发服务器转码。',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HardwareDecodingOption extends StatelessWidget {
  const _HardwareDecodingOption({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final HardwareDecodingMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${mode.label}，${mode.detail}',
      hint: selected ? '当前解码方式' : '选择后自动保存，下次播放生效',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('hardware-decoding-${mode.name}'),
          onTap: enabled ? onSelected : null,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: AppMotion.responsive(context, AppMotion.fast),
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.indigo.withValues(alpha: 0.11)
                  : AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.indigo : AppColors.outline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  mode == HardwareDecodingMode.automatic
                      ? Icons.memory_rounded
                      : Icons.shield_outlined,
                  color: selected ? AppColors.indigo : AppColors.textTertiary,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.label,
                        style: TextStyle(
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        mode.detail,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppColors.indigo,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({
    required this.loading,
    required this.saving,
    required this.error,
  });

  final bool loading;
  final bool saving;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final status = loading
        ? '正在载入'
        : saving
        ? '正在保存'
        : error == null
        ? '已自动保存'
        : '保存失败';
    final statusColor = error == null ? AppColors.success : AppColors.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.spotlight.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.high_quality_rounded,
            color: AppColors.spotlight,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MAX STREAMING BITRATE',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.spotlight),
              ),
              const SizedBox(height: 5),
              Text('播放质量', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 5),
              const Text(
                '为局域网原画或远程播放选择最大视频码率。',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          liveRegion: true,
          label: '播放设置$status',
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  loading
                      ? Icons.hourglass_top_rounded
                      : saving
                      ? Icons.sync_rounded
                      : error == null
                      ? Icons.cloud_done_outlined
                      : Icons.error_outline_rounded,
                  size: 14,
                  color: statusColor,
                ),
                const SizedBox(width: 6),
                Text(
                  status,
                  style: TextStyle(color: statusColor, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BitrateOption extends StatelessWidget {
  const _BitrateOption({
    required this.bitrate,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final PlaybackBitrate bitrate;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${bitrate.label}，${bitrate.detail}',
      hint: selected ? '当前播放质量' : '选择后自动保存',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('playback-bitrate-${bitrate.name}'),
          onTap: enabled ? onSelected : null,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: AppMotion.responsive(context, AppMotion.fast),
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.spotlight.withValues(alpha: 0.09)
                  : AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.spotlight : AppColors.outline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bitrate.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        bitrate.detail,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontFamily: 'Cascadia Mono',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppColors.spotlight,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExternalPlayerConfigCard extends StatefulWidget {
  const _ExternalPlayerConfigCard({
    required this.settings,
    required this.loading,
    required this.saving,
    this.onUseExternalPlayerChanged,
    this.onExternalPlayerPathChanged,
  });

  final PlaybackSettings settings;
  final bool loading;
  final bool saving;
  final ValueChanged<bool>? onUseExternalPlayerChanged;
  final ValueChanged<String?>? onExternalPlayerPathChanged;

  @override
  State<_ExternalPlayerConfigCard> createState() =>
      _ExternalPlayerConfigCardState();
}

class _ExternalPlayerConfigCardState extends State<_ExternalPlayerConfigCard> {
  ExternalPlayerDescriptor? _detected;
  bool _testingLaunch = false;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final service = const ExternalPlayerService();
    final detected = await service.detectExternalPlayer();
    if (mounted) {
      setState(() => _detected = detected);
    }
  }

  Future<void> _pickExecutable() async {
    const typeGroup = XTypeGroup(
      label: '可执行程序',
      extensions: ['exe'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null && mounted) {
      widget.onExternalPlayerPathChanged?.call(file.path);
    }
  }

  Future<void> _testLaunch(String executablePath) async {
    setState(() => _testingLaunch = true);
    try {
      if (File(executablePath).existsSync()) {
        await Process.start(
          executablePath,
          [],
          mode: ProcessStartMode.detached,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已成功启动外部播放器：$executablePath')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('指定的播放器文件不存在，请重新选择。')),
          );
        }
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动外部播放器失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _testingLaunch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final activePath = settings.externalPlayerPath ?? _detected?.executablePath;
    final hasValidFile = activePath != null && File(activePath).existsSync();
    final isCustomPath = settings.externalPlayerPath != null;
    final enabled =
        !widget.loading && !widget.saving && widget.onUseExternalPlayerChanged != null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: settings.useExternalPlayer
            ? AppColors.indigo.withValues(alpha: 0.11)
            : AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: settings.useExternalPlayer
              ? AppColors.indigo.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.open_in_new_rounded,
                color: settings.useExternalPlayer
                    ? AppColors.indigo
                    : AppColors.textTertiary,
                size: 24,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '默认使用外部播放器播放',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '开启后，在详情页点击“立即播放”直接唤起 PotPlayer / VLC，内置播放器为次选项',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                key: const ValueKey('setting-use-external-player'),
                value: settings.useExternalPlayer,
                activeTrackColor: AppColors.indigo,
                onChanged: enabled ? widget.onUseExternalPlayerChanged : null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: hasValidFile
                            ? const Color(0xFF58C99A).withValues(alpha: 0.16)
                            : Colors.amber.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: hasValidFile
                              ? const Color(0xFF58C99A).withValues(alpha: 0.4)
                              : Colors.amber.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasValidFile
                                ? Icons.check_circle_rounded
                                : Icons.warning_amber_rounded,
                            size: 13,
                            color: hasValidFile
                                ? const Color(0xFF58C99A)
                                : Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasValidFile
                                ? (_detected?.name ?? '已关联外部播放器')
                                : '未检测到播放器',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: hasValidFile
                                  ? const Color(0xFF58C99A)
                                  : Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isCustomPath) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.indigo.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '自定义路径',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.indigo,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  activePath ??
                      '未检测到安装的 PotPlayer，建议点击“更改路径”手动定位 PotPlayer64.exe。',
                  style: TextStyle(
                    fontFamily: 'Cascadia Mono',
                    fontSize: 12,
                    color: hasValidFile
                        ? AppColors.textSecondary
                        : AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          widget.loading || widget.saving ? null : _pickExecutable,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      label: const Text('更改播放器路径...', style: TextStyle(fontSize: 12)),
                    ),
                    if (isCustomPath)
                      TextButton.icon(
                        onPressed: widget.loading || widget.saving
                            ? null
                            : () =>
                                widget.onExternalPlayerPathChanged?.call(null),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        icon: const Icon(Icons.restart_alt_rounded, size: 16),
                        label: const Text('恢复自动检测', style: TextStyle(fontSize: 12)),
                      ),
                    if (hasValidFile)
                      FilledButton.tonalIcon(
                        onPressed: _testingLaunch || widget.loading || widget.saving
                            ? null
                            : () => _testLaunch(activePath),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: _testingLaunch
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_circle_outline_rounded, size: 16),
                        label: const Text('测试启动', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

