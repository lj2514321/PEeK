import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/player/domain/audio_enhancement_settings.dart';
import 'package:flutter/material.dart';

class AudioEnhancementSheet extends StatefulWidget {
  const AudioEnhancementSheet({
    super.key,
    required this.currentAudioMode,
    required this.currentToneMapping,
    required this.onAudioModeChanged,
    required this.onToneMappingChanged,
  });

  final AudioEnhancementMode currentAudioMode;
  final ToneMappingAlgorithm currentToneMapping;
  final ValueChanged<AudioEnhancementMode> onAudioModeChanged;
  final ValueChanged<ToneMappingAlgorithm> onToneMappingChanged;

  @override
  State<AudioEnhancementSheet> createState() => _AudioEnhancementSheetState();
}

class _AudioEnhancementSheetState extends State<AudioEnhancementSheet> {
  late AudioEnhancementMode _audioMode;
  late ToneMappingAlgorithm _toneMapping;

  @override
  void initState() {
    super.initState();
    _audioMode = widget.currentAudioMode;
    _toneMapping = widget.currentToneMapping;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420,
      padding: const EdgeInsets.all(24),
      decoration: AppGlass.decoration(radius: 24, elevated: true),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded, color: AppColors.spotlight),
              const SizedBox(width: 10),
              const Text(
                '音画增强控制引擎',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '音频动态处理与夜间压限 (af)',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in AudioEnhancementMode.values) ...[
                ChoiceChip(
                  label: Text(mode.label),
                  selected: _audioMode == mode,
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
          const SizedBox(height: 20),
          const Text(
            'Tone Mapping 映射算法 (HDR)',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
        ],
      ),
    );
  }
}
