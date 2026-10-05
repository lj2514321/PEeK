import 'dart:async';

import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/presentation/global_playback_coordinator.dart';
import 'package:embyplayer/src/features/player/presentation/playback_runtime.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _FakeRuntime implements PlaybackRuntime {
  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  bool _playing = false;
  Duration _position = Duration.zero;
  bool isDisposed = false;

  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration> get durationStream => _durationController.stream;
  @override
  Stream<Duration> get bufferStream => const Stream.empty();
  @override
  Stream<bool> get bufferingStream => const Stream.empty();
  @override
  Stream<double> get volumeStream => const Stream.empty();
  @override
  Stream<double> get rateStream => const Stream.empty();
  @override
  Stream<Tracks> get tracksStream => const Stream.empty();
  @override
  Stream<Track> get trackStream => const Stream.empty();
  @override
  Stream<bool> get completedStream => const Stream.empty();
  @override
  Stream<String> get errorStream => const Stream.empty();

  @override
  Duration get position => _position;
  @override
  bool get playing => _playing;
  @override
  double get rate => 1.0;
  @override
  Tracks get tracks => const Tracks();

  @override
  Widget buildVideoSurface({required SubtitleViewConfiguration subtitleConfiguration}) {
    return const SizedBox(width: 320, height: 180);
  }

  @override
  Future<void> open(PlaybackPlan plan, {required bool play, Duration? startPosition}) async {}

  @override
  Future<void> play() async {
    _playing = true;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _playingController.add(false);
  }

  @override
  Future<void> playOrPause() async {
    _playing = !_playing;
    _playingController.add(_playing);
  }

  @override
  Future<void> seek(Duration target) async {
    _position = target;
    _positionController.add(target);
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setAudioTrack(AudioTrack track) async {}
  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {}
  @override
  Future<String?> readNativeProperty(String property) async => null;
  @override
  Future<void> setSubtitleDelay(Duration delay) async {}
  @override
  Future<void> setAudioFilter(String af) async {}
  @override
  Future<void> setToneMapping(String algorithm) async {}
  @override
  Future<void> setGlslShaders(List<String> shaderPaths) async {}

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
  }
}

void main() {
  test('GlobalPlaybackCoordinator manages presentation lifecycle and controls', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final coordinator = container.read(globalPlaybackCoordinatorProvider.notifier);
    final runtime = _FakeRuntime();

    // 1. Initial State
    expect(container.read(globalPlaybackCoordinatorProvider).mode, PlaybackPresentationMode.hidden);

    const testItem = MediaItem(
      id: 'm1',
      name: 'Test Movie',
      kind: MediaItemKind.movie,
    );
    final testPlan = PlaybackPlan(
      itemId: 'm1',
      mediaSourceId: 'src1',
      playSessionId: 'sess1',
      streamUri: Uri.parse('http://localhost/video.mp4'),
      method: PlaybackMethod.directPlay,
    );

    // 2. Register Active Playback
    coordinator.registerActivePlayback(
      account: null,
      item: testItem,
      plan: testPlan,
      runtime: runtime,
    );

    expect(container.read(globalPlaybackCoordinatorProvider).mode, PlaybackPresentationMode.full);
    expect(container.read(globalPlaybackCoordinatorProvider).item?.id, 'm1');

    // 3. Play / Pause
    await coordinator.togglePlayPause();
    expect(runtime.playing, isTrue);

    // 4. Seek
    await coordinator.seekRelative(const Duration(seconds: 10));
    expect(runtime.position, const Duration(seconds: 10));

    // 5. Close
    await coordinator.close();
    expect(container.read(globalPlaybackCoordinatorProvider).mode, PlaybackPresentationMode.hidden);
    expect(runtime.isDisposed, isTrue);
  });

  test('GlobalPlaybackCoordinator updates plan startPosition on seek and expand preparation', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final coordinator = container.read(globalPlaybackCoordinatorProvider.notifier);
    final runtime = _FakeRuntime();

    final testPlan = PlaybackPlan(
      itemId: 'm2',
      mediaSourceId: 'src2',
      playSessionId: 'sess2',
      streamUri: Uri.parse('http://localhost/video.mp4'),
      method: PlaybackMethod.directPlay,
      startPosition: Duration.zero,
    );

    coordinator.registerActivePlayback(
      account: null,
      item: const MediaItem(id: 'm2', name: 'Movie 2', kind: MediaItemKind.movie),
      plan: testPlan,
      runtime: runtime,
    );

    // Seek to 15 minutes
    await coordinator.seekRelative(const Duration(minutes: 15));
    expect(container.read(globalPlaybackCoordinatorProvider).position, const Duration(minutes: 15));
  });

  test('GlobalPlaybackCoordinator tracks recentPositions, progress, and effective positions', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final coordinator = container.read(globalPlaybackCoordinatorProvider.notifier);
    final runtime = _FakeRuntime();

    final testPlan = PlaybackPlan(
      itemId: 'ep1',
      mediaSourceId: 'src_ep1',
      playSessionId: 'sess_ep1',
      streamUri: Uri.parse('http://localhost/ep1.mp4'),
      method: PlaybackMethod.directPlay,
      duration: const Duration(minutes: 40),
    );

    coordinator.registerActivePlayback(
      account: null,
      item: const MediaItem(
        id: 'ep1',
        name: 'Episode 1',
        kind: MediaItemKind.episode,
        runTime: Duration(minutes: 40),
      ),
      plan: testPlan,
      runtime: runtime,
    );

    // Initial position before any playback progress
    expect(coordinator.getEffectivePosition('ep1'), isNull);

    // Seek to 10 minutes
    await coordinator.seekRelative(const Duration(minutes: 10));
    expect(coordinator.getEffectivePosition('ep1'), const Duration(minutes: 10));
    expect(
      container.read(globalPlaybackCoordinatorProvider).progressFor('ep1', const Duration(minutes: 40)),
      0.25,
    );

    // Manually record another item position
    coordinator.recordPosition('ep2', const Duration(minutes: 20));
    expect(coordinator.getEffectivePosition('ep2'), const Duration(minutes: 20));

    // Close
    await coordinator.close();
    expect(container.read(globalPlaybackCoordinatorProvider).mode, PlaybackPresentationMode.hidden);
    // Recent position persists after close
    expect(coordinator.getEffectivePosition('ep1'), const Duration(minutes: 10));
    expect(coordinator.getEffectivePosition('ep2'), const Duration(minutes: 20));
  });
}
