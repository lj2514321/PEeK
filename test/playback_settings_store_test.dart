import 'dart:io';

import 'package:embyplayer/src/features/player/data/playback_settings_store.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists the selected streaming bitrate', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peek-playback-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = JsonPlaybackSettingsStore(directory: directory);

    await store.write(
      const PlaybackSettings(maxStreamingBitrate: PlaybackBitrate.mbps20),
    );

    final restored = await JsonPlaybackSettingsStore(
      directory: directory,
    ).read();
    expect(restored.maxStreamingBitrate, PlaybackBitrate.mbps20);
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
}
