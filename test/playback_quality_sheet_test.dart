import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/player/presentation/playback_quality_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lays out quality choices on a compact player window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          backgroundColor: Colors.black,
          body: PlaybackQualitySheet(selected: PlaybackBitrate.mbps20),
        ),
      ),
    );

    expect(find.text('播放画质'), findsOneWidget);
    expect(find.text('当前上限 · 平衡'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('quality-option-original')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('quality-option-mbps5')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returns the selected playback bitrate', (tester) async {
    PlaybackBitrate? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<PlaybackBitrate>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => const PlaybackQualitySheet(
                      selected: PlaybackBitrate.original,
                    ),
                  );
                },
                child: const Text('选择画质'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('选择画质'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quality-option-mbps10')));
    await tester.pumpAndSettle();

    expect(selected, PlaybackBitrate.mbps10);
    expect(tester.takeException(), isNull);
  });
}
