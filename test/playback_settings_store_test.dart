import 'dart:io';

import 'package:embyplayer/src/features/player/data/playback_settings_store.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists the selected playback preferences', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peek-playback-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = JsonPlaybackSettingsStore(directory: directory);

    await store.write(
      const PlaybackSettings(
        maxStreamingBitrate: PlaybackBitrate.mbps20,
        hardwareDecodingMode: HardwareDecodingMode.software,
        subtitlePreferences: SubtitlePreferences(
          appearance: SubtitleAppearance.warm,
          fontSize: 30,
          bottomPadding: 132,
          delayMilliseconds: -400,
        ),
      ),
    );

    final restored = await JsonPlaybackSettingsStore(
      directory: directory,
    ).read();
    expect(restored.maxStreamingBitrate, PlaybackBitrate.mbps20);
    expect(restored.hardwareDecodingMode, HardwareDecodingMode.software);
    expect(restored.subtitlePreferences.appearance, SubtitleAppearance.warm);
    expect(restored.subtitlePreferences.fontSize, 30);
    expect(restored.subtitlePreferences.bottomPadding, 132);
    expect(restored.subtitlePreferences.delayMilliseconds, -400);
  });

  test('uses safe defaults when the settings file is damaged', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peek-playback-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}playback_settings_v1.json',
    );
    await file.writeAsString('{not-json');

    final restored = await JsonPlaybackSettingsStore(
      directory: directory,
    ).read();

    expect(restored, const PlaybackSettings());
  });

  test('falls back to original for an unknown bitrate value', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peek-playback-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}playback_settings_v1.json',
    );
    await file.writeAsString(
      '{"version":1,"maxStreamingBitrate":"future-value"}',
    );

    final restored = await JsonPlaybackSettingsStore(
      directory: directory,
    ).read();

    expect(restored.maxStreamingBitrate, PlaybackBitrate.original);
  });

  test('uses automatic hardware decoding for legacy settings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peek-playback-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}playback_settings_v1.json',
    );
    await file.writeAsString('{"version":1,"maxStreamingBitrate":"mbps20"}');

    final restored = await JsonPlaybackSettingsStore(
      directory: directory,
    ).read();

    expect(restored.maxStreamingBitrate, PlaybackBitrate.mbps20);
    expect(restored.hardwareDecodingMode, HardwareDecodingMode.automatic);
    expect(restored.subtitlePreferences, const SubtitlePreferences());
  });

  test('falls back to automatic for an unknown decoding mode', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peek-playback-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}playback_settings_v1.json',
    );
    await file.writeAsString(
      '{"version":2,"hardwareDecodingMode":"future-value"}',
    );

    final restored = await JsonPlaybackSettingsStore(
      directory: directory,
    ).read();

    expect(restored.hardwareDecodingMode, HardwareDecodingMode.automatic);
  });
}
