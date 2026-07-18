import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/player/domain/playback_diagnostics.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/player/presentation/playback_diagnostics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(375, 640), Size(1280, 800)]) {
    testWidgets('lays out playback diagnostics at ${size.width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(snapshot: _snapshot()));

      expect(
        find.byKey(const ValueKey('playback-diagnostics-panel')),
        findsOneWidget,
      );
      expect(find.text('硬件解码 · D3D11VA'), findsWidgets);
      expect(find.textContaining('视频编码不受支持'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invokes copy, refresh and close actions', (tester) async {
    var copyCount = 0;
    var refreshCount = 0;
    var closeCount = 0;
    await tester.pumpWidget(
      _app(
        snapshot: _snapshot(),
        onCopy: () => copyCount++,
        onRefresh: () => refreshCount++,
        onClose: () => closeCount++,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('diagnostics-copy')));
    await tester.tap(find.byKey(const ValueKey('diagnostics-refresh')));
    await tester.tap(find.byKey(const ValueKey('diagnostics-close')));

    expect(copyCount, 1);
    expect(refreshCount, 1);
    expect(closeCount, 1);
  });

  testWidgets('supports 150 percent text scaling on a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(snapshot: _snapshot(), textScaler: const TextScaler.linear(1.5)),
    );

    expect(
      find.byKey(const ValueKey('playback-diagnostics-panel')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  required PlaybackDiagnosticsSnapshot snapshot,
  VoidCallback? onCopy,
  VoidCallback? onRefresh,
  VoidCallback? onClose,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: PlaybackDiagnosticsPanel(
        snapshot: snapshot,
        loading: false,
        onCopy: onCopy ?? () {},
        onRefresh: onRefresh ?? () {},
        onClose: onClose ?? () {},
      ),
    ),
  );
}

PlaybackDiagnosticsSnapshot _snapshot() {
  return PlaybackDiagnosticsSnapshot(
    sampledAt: DateTime(2026, 7, 19, 16, 30),
    method: PlaybackMethod.transcode,
    requestedDecodingMode: HardwareDecodingMode.automatic,
    serverKind: 'jellyfin',
    serverVersion: '10.11.6',
    sourceProtocol: 'https',
    position: const Duration(minutes: 5),
    bufferedUntil: const Duration(minutes: 5, seconds: 20),
    buffering: false,
    actualDecoder: 'd3d11va',
    videoCodec: 'hevc',
    audioCodec: 'eac3',
    container: 'matroska',
    pixelFormat: 'p010',
    colorPrimaries: 'bt.2020',
    transferFunction: 'pq',
    videoOutput: 'libmpv',
    width: 3840,
    height: 2160,
    frameRate: 23.976,
    videoBitrate: 12500000,
    audioBitrate: 384000,
    cacheDuration: 14.5,
    renderDroppedFrames: 3,
    decoderDroppedFrames: 1,
    transcodingReasons: const ['VideoCodecNotSupported'],
  );
}
