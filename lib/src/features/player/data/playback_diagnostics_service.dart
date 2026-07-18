import 'package:embyplayer/src/features/player/domain/playback_diagnostics.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';

typedef PlaybackPropertyReader = Future<String?> Function(String property);

class PlaybackDiagnosticsService {
  const PlaybackDiagnosticsService();

  static const properties = <String>[
    'hwdec-current',
    'width',
    'height',
    'estimated-vf-fps',
    'video-bitrate',
    'audio-bitrate',
    'demuxer-cache-duration',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'file-format',
    'video-params/pixelformat',
    'video-params/primaries',
    'video-params/gamma',
    'current-vo',
  ];

  Future<PlaybackDiagnosticsSnapshot> collect({
    required PlaybackPropertyReader readProperty,
    required PlaybackPlan plan,
    required HardwareDecodingMode requestedDecodingMode,
    required String serverKind,
    required String serverVersion,
    required Duration position,
    required Duration bufferedUntil,
    required bool buffering,
    String? videoCodec,
    String? audioCodec,
    int? fallbackWidth,
    int? fallbackHeight,
    double? fallbackFrameRate,
    int? fallbackVideoBitrate,
    int? fallbackAudioBitrate,
  }) async {
    final entries = await Future.wait(
      properties.map((property) async {
        try {
          return MapEntry(property, _normalize(await readProperty(property)));
        } on Object {
          return MapEntry<String, String?>(property, null);
        }
      }),
    );
    final values = Map<String, String?>.fromEntries(entries);
    return PlaybackDiagnosticsSnapshot(
      sampledAt: DateTime.now(),
      method: plan.method,
      requestedDecodingMode: requestedDecodingMode,
      serverKind: serverKind,
      serverVersion: serverVersion,
      sourceProtocol: plan.streamUri.scheme.isEmpty
          ? 'unknown'
          : plan.streamUri.scheme,
      position: position,
      bufferedUntil: bufferedUntil,
      buffering: buffering,
      actualDecoder: values['hwdec-current'],
      videoCodec: _normalize(videoCodec),
      audioCodec: _normalize(audioCodec),
      container: values['file-format'],
      pixelFormat: values['video-params/pixelformat'],
      colorPrimaries: values['video-params/primaries'],
      transferFunction: values['video-params/gamma'],
      videoOutput: values['current-vo'],
      width: _parseInt(values['width']) ?? fallbackWidth,
      height: _parseInt(values['height']) ?? fallbackHeight,
      frameRate: _parseDouble(values['estimated-vf-fps']) ?? fallbackFrameRate,
      videoBitrate:
          _parseBitrate(values['video-bitrate']) ??
          fallbackVideoBitrate?.toDouble(),
      audioBitrate:
          _parseBitrate(values['audio-bitrate']) ??
          fallbackAudioBitrate?.toDouble(),
      cacheDuration: _parseDouble(values['demuxer-cache-duration']),
      renderDroppedFrames: _parseInt(values['frame-drop-count']) ?? 0,
      decoderDroppedFrames: _parseInt(values['decoder-frame-drop-count']) ?? 0,
      transcodingReasons: plan.transcodingReasons,
    );
  }

  static String? _normalize(String? value) {
    final text = value?.trim();
    if (text == null ||
        text.isEmpty ||
        text.toLowerCase() == 'n/a' ||
        text.toLowerCase() == 'unavailable') {
      return null;
    }
    return text;
  }

  static int? _parseInt(String? value) {
    final parsed = _parseDouble(value);
    return parsed?.round();
  }

  static double? _parseDouble(String? value) {
    if (value == null) return null;
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  static double? _parseBitrate(String? value) {
    final parsed = _parseDouble(value);
    if (parsed == null) return null;
    final unit = value!.toLowerCase();
    if (unit.contains('mbps') || unit.contains('mb/s')) {
      return parsed * 1000000;
    }
    if (unit.contains('kbps') || unit.contains('kb/s')) {
      return parsed * 1000;
    }
    return parsed;
  }
}
