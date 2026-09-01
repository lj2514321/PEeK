import 'dart:convert';
import 'dart:io';

import 'package:embyplayer/src/core/storage/app_storage_path.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';

abstract interface class PlaybackSettingsStore {
  Future<PlaybackSettings> read();

  Future<void> write(PlaybackSettings settings);
}

class MemoryPlaybackSettingsStore implements PlaybackSettingsStore {
  MemoryPlaybackSettingsStore([this.settings = const PlaybackSettings()]);

  PlaybackSettings settings;

  @override
  Future<PlaybackSettings> read() async => settings;

  @override
  Future<void> write(PlaybackSettings settings) async {
    this.settings = settings;
  }
}

class JsonPlaybackSettingsStore implements PlaybackSettingsStore {
  JsonPlaybackSettingsStore({Directory? directory})
    : _directory = directory ?? _defaultDirectory();

  final Directory _directory;
  PlaybackSettings? _settings;
  Future<void> _writeQueue = Future.value();

  File get _file => File(
    '${_directory.path}${Platform.pathSeparator}playback_settings_v1.json',
  );

  static Directory _defaultDirectory() => AppStoragePath.defaultDirectory;

  @override
  Future<PlaybackSettings> read() async {
    final loaded = _settings;
    if (loaded != null) return loaded;
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          return _settings = PlaybackSettings.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      }
    } on FileSystemException {
      // Playback must remain available when optional preferences cannot load.
    } on FormatException {
      // Ignore a partial or outdated preference file and use safe defaults.
    }
    return _settings = const PlaybackSettings();
  }

  @override
  Future<void> write(PlaybackSettings settings) {
    final snapshot = jsonEncode({'version': 3, ...settings.toJson()});
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      await _directory.create(recursive: true);
      await _file.writeAsString(snapshot, flush: true);
      _settings = settings;
    });
    return _writeQueue;
  }
}
