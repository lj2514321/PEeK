import 'dart:io';

import 'package:embyplayer/src/features/player/data/shader_manager_service.dart';
import 'package:embyplayer/src/features/player/domain/audio_enhancement_settings.dart';
import 'package:embyplayer/src/features/player/domain/audio_equalizer_settings.dart';
import 'package:embyplayer/src/features/player/domain/video_shader_preset.dart';
import 'package:flutter_test/flutter_test.dart';

String combineAudioFilters(List<String> rawFilters) {
  if (rawFilters.isEmpty) return '';
  final inner = <String>[];
  for (final f in rawFilters) {
    if (f.startsWith('lavfi=[') && f.endsWith(']')) {
      inner.add(f.substring(7, f.length - 1));
    } else if (f.isNotEmpty) {
      inner.add(f);
    }
  }
  if (inner.isEmpty) return '';
  return 'lavfi=[${inner.join(',')}]';
}

void main() {
  group('Audio & Video Enhancement Pipeline', () {
    test(
      'Audio filter graph combines multiple lavfi filters into a single FFmpeg graph',
      () {
        expect(combineAudioFilters([]), '');

        final nightMode = AudioEnhancementMode.nightMode.mpvFilter;
        expect(
          combineAudioFilters([nightMode]),
          'lavfi=[dynaudnorm=f=75:g=15:p=0.95]',
        );

        final eq = AudioEqualizerSettings.initial().applyPreset(
          AudioEqualizerPreset.bassBoost,
        );
        final eqFilter = eq.toMpvFilter();
        expect(eqFilter, startsWith('lavfi=[equalizer=f=31'));

        final combined = combineAudioFilters([nightMode, eqFilter]);
        expect(
          combined,
          startsWith('lavfi=[dynaudnorm=f=75:g=15:p=0.95,equalizer=f=31'),
        );
        expect(combined.indexOf('lavfi=['), 0);
        expect(combined.lastIndexOf('lavfi=['), 0); // Exactly one lavfi wrapper
        expect(combined.endsWith(']'), isTrue);
      },
    );

    test(
      'AudioEnhancementMode defines valid libavfilter syntax for all options',
      () {
        for (final mode in AudioEnhancementMode.values) {
          if (mode == AudioEnhancementMode.off) {
            expect(mode.mpvFilter, isEmpty);
          } else {
            expect(mode.mpvFilter, startsWith('lavfi=['));
            expect(mode.mpvFilter, endsWith(']'));
          }
        }
      },
    );

    test(
      'ToneMappingAlgorithm only contains valid mpv tone-mapping algorithms',
      () {
        const allowedMpvValues = {
          'clip',
          'mobius',
          'reinhard',
          'hable',
          'gamma',
          'linear',
          'spline',
          'bt.2390',
          'bt.2446a',
        };
        for (final algo in ToneMappingAlgorithm.values) {
          expect(
            allowedMpvValues.contains(algo.mpvValue),
            isTrue,
            reason:
                '${algo.name} has invalid mpv tone-mapping value: ${algo.mpvValue}',
          );
        }
      },
    );

    test(
      'Shader path normalization eliminates Windows backslashes for mpv compatibility',
      () {
        const windowsPath =
            r'C:\Users\NoName\AppData\Local\PEeK\shaders\Anime4K.glsl';
        final normalized = windowsPath.replaceAll(r'\', '/');
        expect(
          normalized,
          'C:/Users/NoName/AppData/Local/PEeK/shaders/Anime4K.glsl',
        );
        expect(normalized.contains(r'\'), isFalse);
      },
    );

    test(
      'ShaderManagerService extracts valid GLSL with //!HOOK MAIN',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'peek-shader-test-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final service = ShaderManagerService(shadersDirectory: tempDir);
        final paths = await service.getShaderPaths(
          VideoShaderPreset.anime4kModeA,
        );
        expect(paths.length, 2);

        for (final p in paths) {
          final content = File(p).readAsStringSync();
          expect(content, contains('//!HOOK MAIN'));
          expect(content, isNot(contains('//!HOOK LUMA')));
        }
      },
    );
  });
}
