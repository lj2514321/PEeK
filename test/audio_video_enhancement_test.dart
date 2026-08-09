import 'package:embyplayer/src/features/player/domain/audio_enhancement_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Audio/Video Matrix: AudioEnhancementMode generates accurate mpv af filters', () {
    expect(AudioEnhancementMode.off.mpvFilter, '');
    expect(
      AudioEnhancementMode.nightMode.mpvFilter,
      contains('lavfi=[dynaudnorm=f=75:g=15:p=0.95]'),
    );
    expect(
      AudioEnhancementMode.vocalBoost.mpvFilter,
      contains('equalizer=g=3:f=1000:w=200'),
    );
    expect(
      AudioEnhancementMode.bassBoost.mpvFilter,
      contains('equalizer=g=5:f=60:w=100'),
    );
  });

  test('Audio/Video Matrix: ToneMappingAlgorithm maps mpv tone-mapping parameters', () {
    expect(ToneMappingAlgorithm.auto.mpvValue, 'auto');
    expect(ToneMappingAlgorithm.mobius.mpvValue, 'mobius');
    expect(ToneMappingAlgorithm.hable.mpvValue, 'hable');
    expect(ToneMappingAlgorithm.reinhard.mpvValue, 'reinhard');
  });
}
