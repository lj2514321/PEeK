import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The native playback boundary used by [PlaybackPage].
///
/// Keeping media_kit behind this interface lets the page own presentation
/// state without constructing a native player in widget tests.
abstract interface class PlaybackRuntime {
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<Duration> get bufferStream;
  Stream<bool> get bufferingStream;
  Stream<double> get volumeStream;
  Stream<double> get rateStream;
  Stream<Tracks> get tracksStream;
  Stream<Track> get trackStream;
  Stream<bool> get completedStream;
  Stream<String> get errorStream;

  Duration get position;
  bool get playing;
  double get rate;
  Tracks get tracks;

  Widget buildVideoSurface({
    required SubtitleViewConfiguration subtitleConfiguration,
  });

  Future<void> open(
    PlaybackPlan plan, {
    required bool play,
    Duration? startPosition,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);
  Future<void> setAudioTrack(AudioTrack track);
  Future<void> setSubtitleTrack(SubtitleTrack track);
  Future<String?> readNativeProperty(String property);
  Future<void> setSubtitleDelay(Duration delay);
  Future<void> dispose();
}

class MediaKitPlaybackRuntime implements PlaybackRuntime {
  MediaKitPlaybackRuntime({required HardwareDecodingMode decodingMode})
    : _player = Player() {
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        hwdec: decodingMode.mpvValue,
        enableHardwareAcceleration: true,
      ),
    );
  }

  final Player _player;
  late final VideoController _controller;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<Duration> get bufferStream => _player.stream.buffer;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<double> get volumeStream => _player.stream.volume;

  @override
  Stream<double> get rateStream => _player.stream.rate;

  @override
  Stream<Tracks> get tracksStream => _player.stream.tracks;

  @override
  Stream<Track> get trackStream => _player.stream.track;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Duration get position => _player.state.position;

  @override
  bool get playing => _player.state.playing;

  @override
  double get rate => _player.state.rate;

  @override
  Tracks get tracks => _player.state.tracks;

  @override
  Widget buildVideoSurface({
    required SubtitleViewConfiguration subtitleConfiguration,
  }) {
    return Video(
      controller: _controller,
      controls: NoVideoControls,
      subtitleViewConfiguration: subtitleConfiguration,
    );
  }

  @override
  Future<void> open(
    PlaybackPlan plan, {
    required bool play,
    Duration? startPosition,
  }) {
    return _player.open(
      Media(
        plan.streamUri.toString(),
        httpHeaders: plan.httpHeaders,
        start: startPosition ?? plan.startPosition,
      ),
      play: play,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> setAudioTrack(AudioTrack track) => _player.setAudioTrack(track);

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) =>
      _player.setSubtitleTrack(track);

  @override
  Future<String?> readNativeProperty(String property) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return null;
    try {
      return await platform.getProperty(property);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final seconds = delay.inMilliseconds / 1000;
    await platform.setProperty('sub-delay', seconds.toStringAsFixed(3));
  }

  @override
  Future<void> dispose() => _player.dispose();
}
