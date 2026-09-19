import 'package:embyplayer/src/features/player/domain/audio_equalizer_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioEqualizerSettings', () {
    test('initial state is flat with 10 bands and disabled', () {
      final initial = AudioEqualizerSettings.initial();
      expect(initial.enabled, isFalse);
      expect(initial.activePreset, AudioEqualizerPreset.flat);
      expect(initial.bands.length, 10);
      expect(initial.bands.first.frequencyHz, 31);
      expect(initial.bands.first.label, '31Hz');
      expect(initial.bands.last.frequencyHz, 16000);
      expect(initial.bands.last.label, '16kHz');
      expect(initial.bands.every((b) => b.gainDb == 0.0), isTrue);
      expect(initial.toMpvFilter(), isEmpty);
    });

    test('applies preset correctly', () {
      final initial = AudioEqualizerSettings.initial();
      final bassSettings = initial.applyPreset(AudioEqualizerPreset.bassBoost);

      expect(bassSettings.enabled, isTrue);
      expect(bassSettings.activePreset, AudioEqualizerPreset.bassBoost);
      expect(bassSettings.bands[0].gainDb, 6.0);
      expect(bassSettings.bands[1].gainDb, 5.0);
      expect(bassSettings.bands[9].gainDb, 0.0);

      final filterStr = bassSettings.toMpvFilter();
      expect(filterStr, contains('equalizer=f=31:width_type=o:w=1:g=6.0'));
      expect(filterStr, contains('equalizer=f=62:width_type=o:w=1:g=5.0'));
      expect(filterStr, isNot(contains('equalizer=f=16000')));
    });

    test('updating band sets preset to custom and clamps range', () {
      final initial = AudioEqualizerSettings.initial();
      final updated = initial.updateBand(4, 15.0); // 500Hz, clamped to 12.0

      expect(updated.enabled, isTrue);
      expect(updated.activePreset, AudioEqualizerPreset.custom);
      expect(updated.bands[4].gainDb, 12.0);

      final filterStr = updated.toMpvFilter();
      expect(filterStr, 'lavfi=[equalizer=f=500:width_type=o:w=1:g=12.0]');
    });

    test('serializes to and from JSON correctly', () {
      final initial = AudioEqualizerSettings.initial();
      final modified = initial
          .applyPreset(AudioEqualizerPreset.vocalBoost)
          .copyWith(enabled: true);

      final json = modified.toJson();
      final restored = AudioEqualizerSettings.fromJson(json);

      expect(restored.enabled, isTrue);
      expect(restored.activePreset, AudioEqualizerPreset.vocalBoost);
      expect(restored.bands.length, 10);
      for (var i = 0; i < 10; i++) {
        expect(restored.bands[i].gainDb, modified.bands[i].gainDb);
      }
    });

    test('disabled equalizer produces empty mpv filter', () {
      final initial = AudioEqualizerSettings.initial();
      final bassSettings = initial.applyPreset(AudioEqualizerPreset.bassBoost);
      final disabled = bassSettings.copyWith(enabled: false);

      expect(disabled.toMpvFilter(), isEmpty);
    });
  });
}
