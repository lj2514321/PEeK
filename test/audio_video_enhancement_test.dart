import 'package:embyplayer/src/features/player/domain/audio_enhancement_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Audio/Video Matrix: AudioEnhancementMode generates accurate mpv af filters',
    () {
      expect(AudioEnhancementMode.off.mpvFilter, '');
      expect(
        AudioEnhancementMode.nightMode.mpvFilter,
        'lavfi=[dynaudnorm=f=75:g=15:p=0.95]',
      );
      expect(
        AudioEnhancementMode.vocalBoost.mpvFilter,
        'lavfi=[equalizer=f=1000:width_type=h:w=200:g=3]',
      );
      expect(
        AudioEnhancementMode.bassBoost.mpvFilter,
        'lavfi=[equalizer=f=60:width_type=h:w=100:g=5]',
      );
    },
  );

  test(
    'Audio/Video Matrix: ToneMappingAlgorithm maps mpv tone-mapping parameters',
    () {
      expect(ToneMappingAlgorithm.auto.mpvValue, 'mobius');
      expect(ToneMappingAlgorithm.mobius.mpvValue, 'mobius');
      expect(ToneMappingAlgorithm.hable.mpvValue, 'hable');
      expect(ToneMappingAlgorithm.reinhard.mpvValue, 'reinhard');
      expect(ToneMappingAlgorithm.spline.mpvValue, 'spline');
      expect(ToneMappingAlgorithm.bt2390.mpvValue, 'bt.2390');
    },
  );
}
