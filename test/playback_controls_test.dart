import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/presentation/playback_controls.dart';
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
        onRateChanged: (value) => selectedRate = value,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('player-play-pause')));
    await tester.tap(find.byKey(const ValueKey('player-audio')));
    await tester.tap(find.byKey(const ValueKey('player-subtitle')));
    await tester.tap(find.byKey(const ValueKey('player-fullscreen')));
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
    expect(find.text('12:34 / 2:00:00'), findsOneWidget);
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
  ValueChanged<double>? onRateChanged,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: PlaybackControls(
        title: '示例电影',
        method: PlaybackMethod.directPlay,
        visible: true,
        playing: true,
        buffering: false,
        changingSource: false,
        position: const Duration(minutes: 12, seconds: 34),
        duration: const Duration(hours: 2),
        buffer: const Duration(minutes: 28),
        volume: 72,
        rate: 1,
        fullScreen: false,
        audioLabel: '中文 AAC 5.1',
        subtitleLabel: '简体中文',
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
        onFullScreen: onFullScreen ?? () {},
      ),
    ),
  );
}
