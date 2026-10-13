import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/player/domain/audio_enhancement_settings.dart';
import 'package:embyplayer/src/features/player/domain/audio_equalizer_settings.dart';
import 'package:embyplayer/src/features/player/domain/video_shader_preset.dart';
import 'package:flutter/material.dart';

class AudioEnhancementSheet extends StatefulWidget {
  const AudioEnhancementSheet({
    super.key,
    required this.currentAudioMode,
    required this.currentToneMapping,
    required this.currentShaderPreset,
    required this.currentEqualizerSettings,
    required this.onAudioModeChanged,
    required this.onToneMappingChanged,
    required this.onShaderPresetChanged,
    required this.onEqualizerSettingsChanged,
  });

  final AudioEnhancementMode currentAudioMode;
  final ToneMappingAlgorithm currentToneMapping;
  final VideoShaderPreset currentShaderPreset;
  final AudioEqualizerSettings currentEqualizerSettings;
  final ValueChanged<AudioEnhancementMode> onAudioModeChanged;
  final ValueChanged<ToneMappingAlgorithm> onToneMappingChanged;
  final ValueChanged<VideoShaderPreset> onShaderPresetChanged;
  final ValueChanged<AudioEqualizerSettings> onEqualizerSettingsChanged;

  @override
  State<AudioEnhancementSheet> createState() => _AudioEnhancementSheetState();
}

class _AudioEnhancementSheetState extends State<AudioEnhancementSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late AudioEnhancementMode _audioMode;
  late ToneMappingAlgorithm _toneMapping;
  late VideoShaderPreset _shaderPreset;
  late AudioEqualizerSettings _eqSettings;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _audioMode = widget.currentAudioMode;
    _toneMapping = widget.currentToneMapping;
    _shaderPreset = widget.currentShaderPreset;
    _eqSettings = widget.currentEqualizerSettings;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 640,
      constraints: const BoxConstraints(maxHeight: 640),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: AppGlass.decoration(radius: 24, elevated: true),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          _buildTabBar(),
          const SizedBox(height: 16),
          Flexible(
            child: TabBarView(
              controller: _tabController,
              children: [_buildVideoShadersTab(), _buildAudioEqualizerTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.spotlight.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.tune_rounded,
            color: AppColors.spotlight,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '音画升维与调音控制台',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Anime4K / FSR GLSL 画质重构与 10 段专业声学均衡器',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
          splashRadius: 20,
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.spotlight.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.spotlight.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AppColors.spotlight,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: const [
          Tab(
            iconMargin: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_fix_high_rounded, size: 16),
                SizedBox(width: 6),
                Flexible(
                  child: Text('画质超分与色彩', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Tab(
            iconMargin: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.equalizer_rounded, size: 16),
                SizedBox(width: 6),
                Flexible(
                  child: Text('10段图形均衡器', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoShadersTab() {
    return PeekSmoothScroll(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'GLSL 画面增强与超分辨率着色器',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  'libmpv 动态挂载',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...VideoShaderPreset.values.map(_buildShaderPresetCard),
            const SizedBox(height: 20),
            const Text(
              'HDR 色调映射算法 (Tone Mapping)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final algorithm in ToneMappingAlgorithm.values) ...[
                  ChoiceChip(
                    label: Text(algorithm.label),
                    selected: _toneMapping == algorithm,
                    selectedColor: AppColors.spotlight.withValues(alpha: 0.25),
                    side: BorderSide(
                      color: _toneMapping == algorithm
                          ? AppColors.spotlight
                          : Colors.white12,
                    ),
                    labelStyle: TextStyle(
                      color: _toneMapping == algorithm
                          ? AppColors.spotlight
                          : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _toneMapping = algorithm);
                        widget.onToneMappingChanged(algorithm);
                      }
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildShaderPresetCard(VideoShaderPreset preset) {
    final isSelected = _shaderPreset == preset;
    Color loadColor = AppColors.cyan;
    if (preset.gpuLoad.contains('高负载')) {
      loadColor = const Color(0xFFFF9800);
    } else if (preset.gpuLoad.contains('中')) {
      loadColor = AppColors.spotlight;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _shaderPreset = preset);
            widget.onShaderPresetChanged(preset);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.spotlight.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.spotlight.withValues(alpha: 0.8)
                    : Colors.white10,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: isSelected ? AppColors.spotlight : Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            preset.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: loadColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              preset.gpuLoad,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: loadColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        preset.description,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary.withValues(alpha: 0.9),
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
    );
  }

  Widget _buildAudioEqualizerTab() {
    return PeekSmoothScroll(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '10 段图形均衡器 (Graphic Equalizer)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'FFmpeg 高保真声学滤波 · -12dB ~ +12dB',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Switch(
                  value: _eqSettings.enabled,
                  activeThumbColor: AppColors.spotlight,
                  onChanged: (val) {
                    final updated = _eqSettings.copyWith(enabled: val);
                    setState(() => _eqSettings = updated);
                    widget.onEqualizerSettingsChanged(updated);
                  },
                ),
                IconButton(
                  tooltip: '重置为原音直通 (Flat)',
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: Colors.white70,
                  ),
                  onPressed: () {
                    final updated = _eqSettings.applyPreset(
                      AudioEqualizerPreset.flat,
                    );
                    setState(() => _eqSettings = updated);
                    widget.onEqualizerSettingsChanged(updated);
                  },
                  splashRadius: 18,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Acoustic Presets
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: AudioEqualizerPreset.values
                    .map((preset) {
                      final isSelected = _eqSettings.activePreset == preset;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(preset.label),
                          selected: isSelected,
                          selectedColor: AppColors.spotlight.withValues(
                            alpha: 0.25,
                          ),
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.spotlight
                                : Colors.white12,
                          ),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? AppColors.spotlight
                                : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              final updated = _eqSettings.applyPreset(preset);
                              setState(() => _eqSettings = updated);
                              widget.onEqualizerSettingsChanged(updated);
                            }
                          },
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 14),
            // 10-Band Sliders Console
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth =
                      (constraints.maxWidth / _eqSettings.bands.length).clamp(
                        38.0,
                        56.0,
                      );
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var i = 0; i < _eqSettings.bands.length; i++)
                          _buildBandSlider(i, itemWidth),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            // Dynamic Audio Processing Section
            const Text(
              '声场动态扩展与夜间防打扰 (Dynamic Audio Processing)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in AudioEnhancementMode.values) ...[
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: _audioMode == mode,
                    selectedColor: AppColors.spotlight.withValues(alpha: 0.25),
                    side: BorderSide(
                      color: _audioMode == mode
                          ? AppColors.spotlight
                          : Colors.white12,
                    ),
                    labelStyle: TextStyle(
                      color: _audioMode == mode
                          ? AppColors.spotlight
                          : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _audioMode = mode);
                        widget.onAudioModeChanged(mode);
                      }
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildBandSlider(int index, double width) {
    final band = _eqSettings.bands[index];
    final isBoost = band.gainDb > 0.05;
    final isCut = band.gainDb < -0.05;

    Color gainColor = AppColors.textTertiary;
    if (_eqSettings.enabled) {
      if (isBoost) gainColor = AppColors.spotlight;
      if (isCut) gainColor = AppColors.cyan;
    }

    return SizedBox(
      width: width,
      height: 175,
      child: Column(
        children: [
          Text(
            '${band.gainDb > 0 ? '+' : ''}${band.gainDb.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: gainColor,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: _eqSettings.enabled
                      ? AppColors.spotlight
                      : Colors.white24,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: _eqSettings.enabled
                      ? AppColors.spotlight
                      : Colors.white38,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                    elevation: 2,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: band.gainDb,
                  min: -12.0,
                  max: 12.0,
                  divisions: 48,
                  onChanged: _eqSettings.enabled
                      ? (value) {
                          final updated = _eqSettings.updateBand(index, value);
                          setState(() => _eqSettings = updated);
                          widget.onEqualizerSettingsChanged(updated);
                        }
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            band.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
