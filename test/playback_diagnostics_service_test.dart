import 'package:embyplayer/src/features/player/data/playback_diagnostics_service.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collects supported libmpv playback properties', () async {
    const service = PlaybackDiagnosticsService();
    final values = <String, String>{
      'hwdec-current': 'd3d11va',
      'width': '3840',
      'height': '2160',
      'estimated-vf-fps': '23.976',
      'video-bitrate': '12500000',
      'audio-bitrate': '384000',
      'demuxer-cache-duration': '14.5',
      'frame-drop-count': '3',
      'decoder-frame-drop-count': '1',
      'file-format': 'matroska',
      'video-params/pixelformat': 'p010',
      'video-params/primaries': 'bt.2020',
      'video-params/gamma': 'pq',
      'current-vo': 'libmpv',
    };
    final plan = PlaybackPlan(
      itemId: 'item-id',
      mediaSourceId: 'source-id',
      playSessionId: 'session-id',
      streamUri: Uri.parse(
        'https://media.example.test/video.m3u8?api_key=secret',
      ),
      method: PlaybackMethod.transcode,
      transcodingReasons: const ['VideoCodecNotSupported'],
    );

    final snapshot = await service.collect(
      readProperty: (property) async => values[property],
      plan: plan,
      requestedDecodingMode: HardwareDecodingMode.automatic,
      serverKind: 'jellyfin',
      serverVersion: '10.11.6',
      position: const Duration(minutes: 5),
      bufferedUntil: const Duration(minutes: 5, seconds: 20),
      buffering: false,
      videoCodec: 'hevc',
      audioCodec: 'eac3',
    );

    expect(snapshot.decoderLabel, '硬件解码 · D3D11VA');
    expect(snapshot.resolutionLabel, '3840 × 2160');
    expect(snapshot.frameRateLabel, '23.976 FPS');
    expect(snapshot.videoBitrateLabel, '12.5 Mbps');
    expect(snapshot.audioBitrateLabel, '384 Kbps');
    expect(snapshot.cacheLabel, '14.5 秒');
    expect(snapshot.droppedFramesLabel, '3 渲染 / 1 解码');
    expect(snapshot.colorLabel, 'BT.2020 · PQ · P010');
    final copied = snapshot.toClipboardText();
    expect(copied, contains('服务器转码'));
    expect(copied, contains('VideoCodecNotSupported'));
    expect(copied, isNot(contains('media.example.test')));
    expect(copied, isNot(contains('secret')));
    expect(copied, isNot(contains('item-id')));
  });

  test(
    'falls back to media track metadata when properties are unavailable',
    () async {
      const service = PlaybackDiagnosticsService();
      final plan = PlaybackPlan(
        itemId: 'item-id',
        mediaSourceId: 'source-id',
        playSessionId: 'session-id',
        streamUri: Uri.parse('http://media.example.test/video.mkv'),
        method: PlaybackMethod.directPlay,
      );

      final snapshot = await service.collect(
        readProperty: (_) async => throw StateError('not available'),
        plan: plan,
        requestedDecodingMode: HardwareDecodingMode.software,
        serverKind: 'emby',
        serverVersion: '4.9',
        position: const Duration(seconds: 10),
        bufferedUntil: const Duration(seconds: 18),
        buffering: true,
        fallbackWidth: 1920,
        fallbackHeight: 1080,
        fallbackFrameRate: 24,
        fallbackVideoBitrate: 8000000,
        fallbackAudioBitrate: 192000,
      );

      expect(snapshot.decoderLabel, '正在读取');
      expect(snapshot.resolutionLabel, '1920 × 1080');
      expect(snapshot.frameRateLabel, '24 FPS');
      expect(snapshot.cacheLabel, '8 秒');
      expect(snapshot.buffering, isTrue);
    },
  );
}
