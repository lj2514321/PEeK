import 'package:embyplayer/src/features/player/presentation/playback_gesture_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestApp({
    Duration position = const Duration(minutes: 5),
    Duration duration = const Duration(minutes: 20),
    double volume = 0.5,
    ValueChanged<double>? onVolumeChanged,
    ValueChanged<Duration>? onSeek,
    VoidCallback? onPlayPause,
    VoidCallback? onToggleControls,
    VoidCallback? onSeekBack10,
    VoidCallback? onSeekForward10,
    bool isLocked = false,
    ValueChanged<bool>? onLockChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 450,
            child: PlaybackGestureOverlay(
              position: position,
              duration: duration,
              volume: volume,
              isLocked: isLocked,
              onLockChanged: onLockChanged,
              onVolumeChanged: onVolumeChanged ?? (_) {},
              onSeek: onSeek ?? (_) {},
              onPlayPause: onPlayPause ?? () {},
              onToggleControls: onToggleControls ?? () {},
              onSeekBack10: onSeekBack10 ?? () {},
              onSeekForward10: onSeekForward10 ?? () {},
              child: Container(color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('PlaybackGestureOverlay handles single tap for toggling controls', (tester) async {
    var toggleCount = 0;
    await tester.pumpWidget(buildTestApp(
      onToggleControls: () => toggleCount++,
    ));

    await tester.tap(find.byType(PlaybackGestureOverlay));
    await tester.pump(const Duration(milliseconds: 400));

    expect(toggleCount, 1);
  });

  testWidgets('PlaybackGestureOverlay handles double tap zones correctly', (tester) async {
    var seekBackCount = 0;
    var seekForwardCount = 0;
    var playPauseCount = 0;

    await tester.pumpWidget(buildTestApp(
      onSeekBack10: () => seekBackCount++,
      onSeekForward10: () => seekForwardCount++,
      onPlayPause: () => playPauseCount++,
    ));

    final overlay = find.byType(PlaybackGestureOverlay);

    // Double tap left (x = 100 in 800-wide widget -> < 35%)
    await tester.tapAt(tester.getTopLeft(overlay) + const Offset(100, 200));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getTopLeft(overlay) + const Offset(100, 200));
    await tester.pump(const Duration(milliseconds: 50));
    expect(seekBackCount, 1);

    // Double tap right (x = 700 in 800-wide widget -> > 65%)
    await tester.tapAt(tester.getTopLeft(overlay) + const Offset(700, 200));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getTopLeft(overlay) + const Offset(700, 200));
    await tester.pump(const Duration(milliseconds: 50));
    expect(seekForwardCount, 1);

    // Double tap center (x = 400 in 800-wide widget)
    await tester.tapAt(tester.getTopLeft(overlay) + const Offset(400, 200));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getTopLeft(overlay) + const Offset(400, 200));
    await tester.pump(const Duration(milliseconds: 50));
    expect(playPauseCount, 1);

    // Allow double-tap and feedback timers to complete cleanly
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('PlaybackGestureOverlay ignores gestures when isLocked is true', (tester) async {
    var toggleCount = 0;
    var seekBackCount = 0;

    await tester.pumpWidget(buildTestApp(
      isLocked: true,
      onToggleControls: () => toggleCount++,
      onSeekBack10: () => seekBackCount++,
    ));

    await tester.tap(find.byType(PlaybackGestureOverlay));
    await tester.pump(const Duration(milliseconds: 400));
    expect(toggleCount, 0);

    final overlay = find.byType(PlaybackGestureOverlay);
    await tester.tapAt(tester.getTopLeft(overlay) + const Offset(100, 200));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getTopLeft(overlay) + const Offset(100, 200));
    await tester.pump(const Duration(seconds: 1));
    expect(seekBackCount, 0);
  });
}
