import 'package:embyplayer/src/features/player/domain/audio_enhancement_settings.dart';
import 'package:embyplayer/src/features/player/domain/audio_equalizer_settings.dart';
import 'package:embyplayer/src/features/player/domain/video_shader_preset.dart';
import 'package:embyplayer/src/features/player/presentation/audio_enhancement_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AudioEnhancementSheet renders and switches tabs and selects presets', (tester) async {
    VideoShaderPreset selectedShader = VideoShaderPreset.off;
    ToneMappingAlgorithm selectedTone = ToneMappingAlgorithm.auto;
    AudioEnhancementMode selectedAudioMode = AudioEnhancementMode.off;
    AudioEqualizerSettings selectedEq = AudioEqualizerSettings.initial();

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AudioEnhancementSheet(
              currentAudioMode: selectedAudioMode,
              currentToneMapping: selectedTone,
              currentShaderPreset: selectedShader,
              currentEqualizerSettings: selectedEq,
              onAudioModeChanged: (mode) => selectedAudioMode = mode,
              onToneMappingChanged: (tone) => selectedTone = tone,
              onShaderPresetChanged: (preset) => selectedShader = preset,
              onEqualizerSettingsChanged: (eq) => selectedEq = eq,
            ),
          ),
        ),
      ),
    );

    // Verify Title & Header
    expect(find.text('音画升维与调音控制台'), findsOneWidget);
    expect(find.text('画质超分与色彩'), findsOneWidget);
    expect(find.text('10段图形均衡器'), findsOneWidget);

    // Tab 1: Video Shaders
    expect(find.text('Anime4K 极致重构 (Mode A)'), findsOneWidget);
    expect(find.text('AMD FidelityFX FSR 超分'), findsOneWidget);
    expect(find.text('CAS 对比度自适应锐化'), findsOneWidget);

    // Tap on FSR preset card
    await tester.tap(find.text('AMD FidelityFX FSR 超分'));
    await tester.pumpAndSettle();
    expect(selectedShader, VideoShaderPreset.fsr);

    // Switch to Tab 2
    await tester.tap(find.text('10段图形均衡器'));
    await tester.pumpAndSettle();

    // Verify Tab 2 elements
    expect(find.text('10 段图形均衡器 (Graphic Equalizer)'), findsOneWidget);
    expect(find.text('澎湃重低音'), findsOneWidget);
    expect(find.text('31Hz'), findsOneWidget);
    expect(find.text('16kHz'), findsOneWidget);

    // Tap Bass Boost preset
    await tester.tap(find.text('澎湃重低音'));
    await tester.pumpAndSettle();
    expect(selectedEq.activePreset, AudioEqualizerPreset.bassBoost);
    expect(selectedEq.enabled, isTrue);
  });
}
