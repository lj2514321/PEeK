import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/player/presentation/playback_controls.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(375, 640), Size(820, 560), Size(1280, 800)]) {
    testWidgets('lays out playback controls at ${size.width.toInt()} pixels', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_controlsApp());

      expect(find.text('示例电影'), findsOneWidget);
      expect(find.byKey(const ValueKey('player-play-pause')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-audio')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-subtitle')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-fullscreen')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-diagnostics')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-quality')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-episodes')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-chapters')), findsOneWidget);
      expect(find.byKey(const ValueKey('chapter-marker-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invokes playback, seeking, track and rate actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var playPauseCount = 0;
    var audioCount = 0;
    var subtitleCount = 0;
    var fullScreenCount = 0;
    var previousCount = 0;
    var nextCount = 0;
    var episodesCount = 0;
    var diagnosticsCount = 0;
    var chaptersCount = 0;
    var qualityCount = 0;
    Duration? previewPosition;
    Duration? seekPosition;
    double? selectedRate;

    await tester.pumpWidget(
      _controlsApp(
        onPlayPause: () => playPauseCount++,
        onSeekPreview: (value) => previewPosition = value,
        onSeek: (value) => seekPosition = value,
        onAudio: () => audioCount++,
        onSubtitle: () => subtitleCount++,
        onFullScreen: () => fullScreenCount++,
        onPrevious: () => previousCount++,
        onNext: () => nextCount++,
        onEpisodes: () => episodesCount++,
        onDiagnostics: () => diagnosticsCount++,
        onChapters: () => chaptersCount++,
        onQuality: () => qualityCount++,
        onRateChanged: (value) => selectedRate = value,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('player-play-pause')));
    await tester.tap(find.byKey(const ValueKey('player-audio')));
    await tester.tap(find.byKey(const ValueKey('player-subtitle')));
    await tester.tap(find.byKey(const ValueKey('player-fullscreen')));
    await tester.tap(find.byKey(const ValueKey('player-previous')));
    await tester.tap(find.byKey(const ValueKey('player-next')));
    await tester.tap(find.byKey(const ValueKey('player-episodes')));
    await tester.tap(find.byKey(const ValueKey('player-diagnostics')));
    await tester.tap(find.byKey(const ValueKey('player-chapters')));
    await tester.tap(find.byKey(const ValueKey('player-quality')));
    await tester.drag(
      find.byKey(const ValueKey('player-seek')),
      const Offset(90, 0),
    );
    await tester.tap(find.byKey(const ValueKey('player-rate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5x'));
    await tester.pumpAndSettle();

    expect(playPauseCount, 1);
    expect(audioCount, 1);
    expect(subtitleCount, 1);
    expect(fullScreenCount, 1);
    expect(previousCount, 1);
    expect(nextCount, 1);
    expect(episodesCount, 1);
    expect(diagnosticsCount, 1);
    expect(chaptersCount, 1);
    expect(qualityCount, 1);
    expect(previewPosition, isNotNull);
    expect(seekPosition, isNotNull);
    expect(selectedRate, 1.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses compact controls without the volume slider', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_controlsApp());

    expect(find.byKey(const ValueKey('player-volume')), findsNothing);
    expect(find.byKey(const ValueKey('player-previous')), findsNothing);
    expect(find.byKey(const ValueKey('player-next')), findsNothing);
    expect(find.byKey(const ValueKey('player-episodes')), findsOneWidget);
    expect(find.text('12:34'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows responsive next episode countdown and actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var playNowCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: NextEpisodeCountdown(
            item: const MediaItem(
              id: 'episode-2',
              name: '第二集',
              kind: MediaItemKind.episode,
              parentIndexNumber: 1,
              indexNumber: 2,
            ),
            secondsRemaining: 6,
            totalSeconds: 8,
            onPlayNow: () => playNowCount++,
            onCancel: () => cancelCount++,
          ),
        ),
      ),
    );

    expect(find.text('即将播放下一集'), findsOneWidget);
    expect(find.text('S01E02 · 第二集'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('next-episode-play-now')));
    await tester.tap(find.byKey(const ValueKey('next-episode-cancel')));
    expect(playNowCount, 1);
    expect(cancelCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows compact transient feedback for keyboard seeking', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: PlaybackSeekFeedback(
              deltaSeconds: 20,
              position: Duration(minutes: 42, seconds: 8),
            ),
          ),
        ),
      ),
    );

    expect(find.text('快进 20 秒'), findsOneWidget);
    expect(find.text('42:08'), findsOneWidget);
    expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _controlsApp({
  VoidCallback? onPlayPause,
  ValueChanged<Duration>? onSeekPreview,
  ValueChanged<Duration>? onSeek,
  VoidCallback? onAudio,
  VoidCallback? onSubtitle,
  VoidCallback? onFullScreen,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  VoidCallback? onEpisodes,
  VoidCallback? onDiagnostics,
  VoidCallback? onChapters,
  VoidCallback? onQuality,
  ValueChanged<double>? onRateChanged,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: PlaybackControls(
        title: '示例电影',
        method: PlaybackMethod.directPlay,
        quality: PlaybackBitrate.original,
        visible: true,
        playing: true,
        buffering: false,
        changingSource: false,
        sourceChangeLabel: '正在切换至平衡',
        position: const Duration(minutes: 12, seconds: 34),
        duration: const Duration(hours: 2),
        buffer: const Duration(minutes: 28),
        volume: 72,
        rate: 1,
        fullScreen: false,
        audioLabel: '中文 AAC 5.1',
        subtitleLabel: '简体中文',
        chapters: const [
          MediaChapter(name: '开场', startPosition: Duration.zero),
          MediaChapter(name: '第一次转折', startPosition: Duration(minutes: 30)),
          MediaChapter(name: '终幕', startPosition: Duration(minutes: 90)),
        ],
        queueAvailable: true,
        canPrevious: true,
        canNext: true,
        onBack: () {},
        onPlayPause: onPlayPause ?? () {},
        onSeekPreview: onSeekPreview ?? (_) {},
        onSeek: onSeek ?? (_) {},
        onSeekBack: () {},
        onSeekForward: () {},
        onVolumeChanged: (_) {},
        onMute: () {},
        onRateChanged: onRateChanged ?? (_) {},
        onAudio: onAudio ?? () {},
        onSubtitle: onSubtitle ?? () {},
        onChapters: onChapters ?? () {},
        onPrevious: onPrevious ?? () {},
        onNext: onNext ?? () {},
        onEpisodes: onEpisodes ?? () {},
        onDiagnostics: onDiagnostics ?? () {},
        onQuality: onQuality ?? () {},
        onFullScreen: onFullScreen ?? () {},
      ),
    ),
  );
}
