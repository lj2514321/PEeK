import 'dart:io';

import 'package:embyplayer/src/features/player/data/shader_manager_service.dart';
import 'package:embyplayer/src/features/player/domain/video_shader_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoShaderPreset', () {
    test('off preset has empty shaders and is not enabled', () {
      expect(VideoShaderPreset.off.isEnabled, isFalse);
      expect(VideoShaderPreset.off.shaderFilenames, isEmpty);
      expect(VideoShaderPreset.fromId('off'), VideoShaderPreset.off);
    });

    test('anime4k presets have correct shader lists', () {
      expect(VideoShaderPreset.anime4kModeA.isEnabled, isTrue);
      expect(VideoShaderPreset.anime4kModeA.shaderFilenames, [
        'Anime4K_Restore_CNN_M.glsl',
        'Anime4K_Upscale_CNN_x2_M.glsl',
      ]);
      expect(
        VideoShaderPreset.fromId('anime4k_a'),
        VideoShaderPreset.anime4kModeA,
      );

      expect(VideoShaderPreset.anime4kModeB.isEnabled, isTrue);
      expect(VideoShaderPreset.anime4kModeB.shaderFilenames, [
        'Anime4K_Clamp_Highlights.glsl',
        'Anime4K_Restore_CNN_Soft_M.glsl',
      ]);
    });

    test('fsr and cas presets have correct shader lists', () {
      expect(VideoShaderPreset.fsr.shaderFilenames, [
        'FSR_EASU.glsl',
        'FSR_RCAS.glsl',
      ]);
      expect(VideoShaderPreset.cas.shaderFilenames, ['CAS.glsl']);
    });
  });

  group('ShaderManagerService', () {
    test('returns empty list for off preset', () async {
      final service = ShaderManagerService();
      final paths = await service.getShaderPaths(VideoShaderPreset.off);
      expect(paths, isEmpty);
    });

    test('extracts and returns shader file paths for active presets', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'peek_shader_test_',
      );
      try {
        final service = ShaderManagerService(shadersDirectory: tempDir);
        final paths = await service.getShaderPaths(VideoShaderPreset.cas);

        expect(paths.length, 1);
        final file = File(paths.first);
        expect(await file.exists(), isTrue);
        expect(paths.first.endsWith('CAS.glsl'), isTrue);

        final content = await file.readAsString();
        expect(content, contains('CAS'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
