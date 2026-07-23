import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SystemMediaPlaybackState { stopped, paused, playing, changing }

enum SystemMediaCommandType { play, pause, next, previous, stop, seek }

class SystemMediaCommand {
  const SystemMediaCommand(this.type, {this.position});

  final SystemMediaCommandType type;
  final Duration? position;
}

class SystemAudioVolume {
  const SystemAudioVolume({required this.level, required this.muted});

  final double level;
  final bool muted;

  double get effectiveLevel => muted ? 0 : level;
}

class SystemMediaMetadata {
  const SystemMediaMetadata({
    required this.title,
    this.subtitle,
    this.artworkUri,
    this.artworkHeaders = const {},
  });

  final String title;
  final String? subtitle;
  final Uri? artworkUri;
  final Map<String, String> artworkHeaders;
}

typedef SystemMediaCommandHandler =
    FutureOr<void> Function(SystemMediaCommand command);
typedef SystemVolumeHandler = void Function(SystemAudioVolume volume);

abstract interface class SystemMediaSession {
  Future<bool> initialize({
    required SystemMediaCommandHandler onCommand,
    required SystemVolumeHandler onVolumeChanged,
    required VoidCallback onVolumeSessionDisconnected,
  });

  Future<void> updateMetadata(SystemMediaMetadata metadata);

  Future<void> updatePlayback({
    required SystemMediaPlaybackState state,
    required bool canPrevious,
    required bool canNext,
  });

  Future<void> updateTimeline({
    required Duration position,
    required Duration duration,
    required double playbackRate,
  });

  Future<SystemAudioVolume?> bindVolume();

  Future<void> setVolume(double level);

  Future<void> clear();

  Future<void> dispose();
}

final windowsMediaSessionProvider = Provider<SystemMediaSession Function()>((
  ref,
) {
  return WindowsMediaSession.new;
});

class WindowsMediaSession implements SystemMediaSession {
  WindowsMediaSession({
    MethodChannel? channel,
    bool Function()? isWindows,
    this._cacheManager,
  }) : _channel = channel ?? const MethodChannel('peek/windows_media_session'),
       _isWindows = isWindows ?? (() => Platform.isWindows);

  final MethodChannel _channel;
  final bool Function() _isWindows;
  BaseCacheManager? _cacheManager;

  SystemMediaCommandHandler? _onCommand;
  SystemVolumeHandler? _onVolumeChanged;
  VoidCallback? _onVolumeSessionDisconnected;
  bool _available = false;
  int _metadataGeneration = 0;

  @override
  Future<bool> initialize({
    required SystemMediaCommandHandler onCommand,
    required SystemVolumeHandler onVolumeChanged,
    required VoidCallback onVolumeSessionDisconnected,
  }) async {
    if (!_isWindows()) return false;
    _onCommand = onCommand;
    _onVolumeChanged = onVolumeChanged;
    _onVolumeSessionDisconnected = onVolumeSessionDisconnected;
    _channel.setMethodCallHandler(_handleNativeCall);
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'initialize',
      );
      _available = result?['available'] == true;
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    }
    return _available;
  }

  @override
  Future<void> updateMetadata(SystemMediaMetadata metadata) async {
    if (!_available) return;
    final generation = ++_metadataGeneration;
    final arguments = <String, Object?>{
      'title': metadata.title,
      'subtitle': metadata.subtitle,
    };
    await _invoke('updateMetadata', arguments);

    final artworkUri = metadata.artworkUri;
    if (artworkUri == null) return;
    try {
      final artwork = await (_cacheManager ??= DefaultCacheManager())
          .getSingleFile(
            artworkUri.toString(),
            headers: metadata.artworkHeaders,
          );
      if (!_available || generation != _metadataGeneration) return;
      await _invoke('updateMetadata', {
        ...arguments,
        'artworkPath': artwork.path,
      });
    } on Object {
      // Metadata should remain useful even when artwork is unavailable.
    }
  }

  @override
  Future<void> updatePlayback({
    required SystemMediaPlaybackState state,
    required bool canPrevious,
    required bool canNext,
  }) {
    return _invoke('updatePlayback', {
      'state': state.name,
      'canPrevious': canPrevious,
      'canNext': canNext,
    });
  }

  @override
  Future<void> updateTimeline({
    required Duration position,
    required Duration duration,
    required double playbackRate,
  }) {
    return _invoke('updateTimeline', {
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'playbackRate': playbackRate,
    });
  }

  @override
  Future<SystemAudioVolume?> bindVolume() async {
    if (!_available) return null;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'bindVolume',
      );
      final rawLevel = result?['level'];
      if (rawLevel is! num) return null;
      return SystemAudioVolume(
        level: rawLevel.toDouble().clamp(0, 100),
        muted: result?['muted'] == true,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> setVolume(double level) {
    return _invoke('setVolume', {'level': level.clamp(0, 100)});
  }

  @override
  Future<void> clear() async {
    _metadataGeneration++;
    await _invoke('clear');
  }

  @override
  Future<void> dispose() async {
    _metadataGeneration++;
    await _invoke('dispose');
    _available = false;
    _onCommand = null;
    _onVolumeChanged = null;
    _onVolumeSessionDisconnected = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    final arguments = call.arguments;
    if (arguments is! Map) return;
    switch (call.method) {
      case 'command':
        final type = switch (arguments['type']) {
          'play' => SystemMediaCommandType.play,
          'pause' => SystemMediaCommandType.pause,
          'next' => SystemMediaCommandType.next,
          'previous' => SystemMediaCommandType.previous,
          'stop' => SystemMediaCommandType.stop,
          'seek' => SystemMediaCommandType.seek,
          _ => null,
        };
        if (type == null) return;
        final positionMs = arguments['positionMs'];
        await _onCommand?.call(
          SystemMediaCommand(
            type,
            position: positionMs is num
                ? Duration(milliseconds: positionMs.toInt())
                : null,
          ),
        );
      case 'volumeChanged':
        final level = arguments['level'];
        if (level is! num) return;
        _onVolumeChanged?.call(
          SystemAudioVolume(
            level: level.toDouble().clamp(0, 100),
            muted: arguments['muted'] == true,
          ),
        );
      case 'volumeSessionDisconnected':
        _onVolumeSessionDisconnected?.call();
    }
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // System integration is optional and must never interrupt playback.
    }
  }
}
