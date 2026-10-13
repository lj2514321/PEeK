import 'dart:ui';

import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/presentation/floating_mini_player.dart';
import 'package:embyplayer/src/features/player/presentation/global_playback_coordinator.dart';
import 'package:embyplayer/src/features/player/presentation/playback_runtime.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _FakeMiniRuntime implements PlaybackRuntime {
  bool isPlaying = false;
  bool isDisposed = false;

  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get durationStream => const Stream.empty();
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
  Duration get position => const Duration(seconds: 45);
  @override
  bool get playing => isPlaying;
  @override
  double get rate => 1.0;
  @override
  Tracks get tracks => const Tracks();

  @override
  Widget buildVideoSurface({
    required SubtitleViewConfiguration subtitleConfiguration,
  }) {
    return const SizedBox(
      key: ValueKey('fake-mini-video-surface'),
      width: 360,
      height: 202.5,
    );
  }

  @override
  Future<void> open(
    PlaybackPlan plan, {
    required bool play,
    Duration? startPosition,
  }) async {}
  @override
  Future<void> play() async => isPlaying = true;
  @override
  Future<void> pause() async => isPlaying = false;
  @override
  Future<void> playOrPause() async => isPlaying = !isPlaying;
  @override
  Future<void> seek(Duration position) async {}
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
  }
}

void main() {
  testWidgets(
    'renders FloatingMiniPlayer when mode is mini and handles controls',
    (tester) async {
      final runtime = _FakeMiniRuntime();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const testItem = MediaItem(
        id: 'mini-1',
        name: 'Interstellar',
        kind: MediaItemKind.movie,
      );
      final testPlan = PlaybackPlan(
        itemId: 'mini-1',
        mediaSourceId: 'src-1',
        playSessionId: 'sess-1',
        streamUri: Uri.parse('http://localhost/test.mp4'),
        method: PlaybackMethod.directPlay,
      );

      final coordinator = container.read(
        globalPlaybackCoordinatorProvider.notifier,
      );
      coordinator.registerActivePlayback(
        account: null,
        item: testItem,
        plan: testPlan,
        runtime: runtime,
      );

      // Minimize to trigger floating player
      container
          .read(globalPlaybackCoordinatorProvider.notifier)
          .state = container
          .read(globalPlaybackCoordinatorProvider)
          .copyWith(mode: PlaybackPresentationMode.mini);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Stack(children: [FloatingMiniPlayer()])),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('fake-mini-video-surface')),
        findsOneWidget,
      );
      expect(find.text('Interstellar'), findsOneWidget);

      // Hover over mini player to reveal controls
      final miniPlayer = find.byType(FloatingMiniPlayer);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(miniPlayer));
      await tester.pumpAndSettle();

      // Tap Close Button
      final closeBtn = find.byTooltip('关闭播放');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(
        container.read(globalPlaybackCoordinatorProvider).mode,
        PlaybackPresentationMode.hidden,
      );
      expect(runtime.isDisposed, isTrue);
    },
  );
}
