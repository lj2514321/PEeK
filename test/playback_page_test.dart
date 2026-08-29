import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/app_chrome.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/player/data/playback_diagnostic_log.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/data/playback_settings_store.dart';
import 'package:embyplayer/src/features/player/data/windows_media_session.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/presentation/playback_page.dart';
import 'package:embyplayer/src/features/player/presentation/playback_runtime.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  testWidgets(
    'opens and disposes an injected playback runtime',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final logDirectory = Directory.systemTemp.createTempSync(
        'peek-player-page-test-',
      );
      addTearDown(() {
        AppChrome.leaveImmersive();
        if (logDirectory.existsSync()) {
          logDirectory.deleteSync(recursive: true);
        }
      });

      final runtime = _FakePlaybackRuntime();
      addTearDown(runtime.closeStreams);
      final playbackService = _RecordingPlaybackService();
      final systemSession = _FakeSystemMediaSession();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackServiceProvider.overrideWithValue(playbackService),
            playbackSettingsStoreProvider.overrideWithValue(
              MemoryPlaybackSettingsStore(),
            ),
            playbackDiagnosticLogProvider.overrideWithValue(
              PlaybackDiagnosticLog(directory: logDirectory),
            ),
            windowsMediaSessionProvider.overrideWithValue(() => systemSession),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    key: const ValueKey('open-player'),
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => PlaybackPage(
                            account: _account,
                            item: _item,
                            plan: _plan,
                            runtime: runtime,
                          ),
                        ),
                      );
                    },
                    child: const Text('打开播放器'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-player')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('fake-video-surface')), findsOneWidget);
      expect(runtime.openCount, 1);
      expect(runtime.openedPlan, same(_plan));
      expect(playbackService.startedCount, 1);
      expect(AppChrome.immersive.value, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();

      expect(runtime.seekCalls, [const Duration(seconds: 20)]);

      // Premature completion event while only at 20s of a 2h movie should NOT mark played
      runtime._completedController.add(true);
      await tester.pump();
      expect(playbackService.markPlayedCount, 0);

      await tester.tap(find.byKey(const ValueKey('player-close')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('open-player')), findsOneWidget);
      expect(runtime.disposeCount, 1);
      expect(systemSession.disposeCount, 1);
      expect(playbackService.stoppedCount, 1);
      expect(AppChrome.immersive.value, isFalse);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}

final _account = AuthenticatedServer(
  server: DiscoveredServer(
    kind: ServerKind.jellyfin,
    name: 'Test server',
    version: '10.11.0',
    serverId: 'server',
    apiBaseUri: _baseUri,
  ),
  userId: 'user',
  userName: 'Tester',
  deviceId: 'device',
  accessToken: 'token',
);

final _baseUri = Uri.parse('http://127.0.0.1:8096');

const _item = MediaItem(
  id: 'movie',
  name: '示例电影',
  kind: MediaItemKind.movie,
  runTime: Duration(hours: 2),
);

final _plan = PlaybackPlan(
  itemId: _item.id,
  mediaSourceId: 'source',
  playSessionId: 'session',
  streamUri: Uri.parse('http://127.0.0.1:8096/Videos/movie/stream'),
  method: PlaybackMethod.directPlay,
  duration: _item.runTime,
);

class _FakePlaybackRuntime implements PlaybackRuntime {
  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _bufferController = StreamController<Duration>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  final _rateController = StreamController<double>.broadcast();
  final _tracksController = StreamController<Tracks>.broadcast();
  final _trackController = StreamController<Track>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  PlaybackPlan? openedPlan;
  int openCount = 0;
  int disposeCount = 0;
  final List<Duration> seekCalls = [];
  Duration _position = Duration.zero;
  bool _playing = false;
  double _rate = 1;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<Duration> get bufferStream => _bufferController.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingController.stream;

  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Stream<double> get rateStream => _rateController.stream;

  @override
  Stream<Tracks> get tracksStream => _tracksController.stream;

  @override
  Stream<Track> get trackStream => _trackController.stream;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  Duration get position => _position;

  @override
  bool get playing => _playing;

  @override
  double get rate => _rate;

  @override
  Tracks get tracks => const Tracks();

  @override
  Widget buildVideoSurface({
    required SubtitleViewConfiguration subtitleConfiguration,
  }) {
    return const ColoredBox(
      key: ValueKey('fake-video-surface'),
      color: Colors.black,
    );
  }

  @override
  Future<void> open(
    PlaybackPlan plan, {
    required bool play,
    Duration? startPosition,
  }) async {
    openCount++;
    openedPlan = plan;
    _position = startPosition ?? plan.startPosition;
    _playing = play;
    _positionController.add(_position);
    if (plan.duration case final duration?) {
      _durationController.add(duration);
    }
    _playingController.add(_playing);
  }

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
  Future<void> playOrPause() => _playing ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    seekCalls.add(position);
    _positionController.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volumeController.add(volume);
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    _rateController.add(rate);
  }

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
  Future<void> dispose() async {
    disposeCount++;
  }

  Future<void> closeStreams() async {
    await Future.wait([
      _playingController.close(),
      _positionController.close(),
      _durationController.close(),
      _bufferController.close(),
      _bufferingController.close(),
      _volumeController.close(),
      _rateController.close(),
      _tracksController.close(),
      _trackController.close(),
      _completedController.close(),
      _errorController.close(),
    ]);
  }
}

class _RecordingPlaybackService extends PlaybackService {
  _RecordingPlaybackService() : super(Dio());

  int startedCount = 0;
  int stoppedCount = 0;
  int markPlayedCount = 0;

  @override
  Future<void> markPlayed(AuthenticatedServer account, String itemId) async {
    markPlayedCount++;
  }

  @override
  Future<void> reportStarted(
    AuthenticatedServer account,
    PlaybackSessionSnapshot snapshot,
  ) async {
    startedCount++;
  }

  @override
  Future<void> reportStopped(
    AuthenticatedServer account,
    PlaybackSessionSnapshot snapshot,
  ) async {
    stoppedCount++;
  }

  @override
  Future<void> reportProgress(
    AuthenticatedServer account,
    PlaybackSessionSnapshot snapshot, {
    String eventName = 'TimeUpdate',
  }) async {}
}

class _FakeSystemMediaSession implements SystemMediaSession {
  int disposeCount = 0;

  @override
  Future<bool> initialize({
    required SystemMediaCommandHandler onCommand,
    required SystemVolumeHandler onVolumeChanged,
    required VoidCallback onVolumeSessionDisconnected,
  }) async {
    return false;
  }

  @override
  Future<SystemAudioVolume?> bindVolume() async => null;

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  @override
  Future<void> setVolume(double level) async {}

  @override
  Future<void> updateMetadata(SystemMediaMetadata metadata) async {}

  @override
  Future<void> updatePlayback({
    required SystemMediaPlaybackState state,
    required bool canPrevious,
    required bool canNext,
  }) async {}

  @override
  Future<void> updateTimeline({
    required Duration position,
    required Duration duration,
    required double playbackRate,
  }) async {}
}
