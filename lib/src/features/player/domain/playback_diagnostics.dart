import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';

class PlaybackDiagnosticsSnapshot {
  const PlaybackDiagnosticsSnapshot({
    required this.sampledAt,
    required this.method,
    required this.requestedDecodingMode,
    required this.serverKind,
    required this.serverVersion,
    required this.sourceProtocol,
    required this.position,
    required this.bufferedUntil,
    required this.buffering,
    this.actualDecoder,
    this.videoCodec,
    this.audioCodec,
    this.container,
    this.pixelFormat,
    this.colorPrimaries,
    this.transferFunction,
    this.videoOutput,
    this.width,
    this.height,
    this.frameRate,
    this.videoBitrate,
    this.audioBitrate,
    this.cacheDuration,
    this.renderDroppedFrames = 0,
    this.decoderDroppedFrames = 0,
    this.transcodingReasons = const [],
  });

  final DateTime sampledAt;
  final PlaybackMethod method;
  final HardwareDecodingMode requestedDecodingMode;
  final String serverKind;
  final String serverVersion;
  final String sourceProtocol;
  final Duration position;
  final Duration bufferedUntil;
  final bool buffering;
  final String? actualDecoder;
  final String? videoCodec;
  final String? audioCodec;
  final String? container;
  final String? pixelFormat;
  final String? colorPrimaries;
  final String? transferFunction;
  final String? videoOutput;
  final int? width;
  final int? height;
  final double? frameRate;
  final double? videoBitrate;
  final double? audioBitrate;
  final double? cacheDuration;
  final int renderDroppedFrames;
  final int decoderDroppedFrames;
  final List<String> transcodingReasons;

  String get methodLabel => switch (method) {
    PlaybackMethod.directPlay => '原码播放',
    PlaybackMethod.directStream => '直接串流',
    PlaybackMethod.transcode => '服务器转码',
  };

  String get decoderLabel {
    final value = actualDecoder?.trim();
    if (value == null || value.isEmpty) return '正在读取';
    if (value.toLowerCase() == 'no') return '软件解码';
    return '硬件解码 · ${value.toUpperCase()}';
  }

  String get resolutionLabel {
    if (width == null || height == null) return '不可用';
    return '$width × $height';
  }

  String get frameRateLabel => frameRate == null
      ? '不可用'
      : '${_trimNumber(frameRate!, fractionDigits: 3)} FPS';

  String get videoBitrateLabel => _formatBitrate(videoBitrate);

  String get audioBitrateLabel => _formatBitrate(audioBitrate);

  String get cacheLabel {
    final mpvCache = cacheDuration;
    if (mpvCache != null) {
      return '${_trimNumber(mpvCache, fractionDigits: 1)} 秒';
    }
    final ahead = bufferedUntil - position;
    return ahead.isNegative ? '0 秒' : '${ahead.inSeconds} 秒';
  }

  String get droppedFramesLabel {
    return '$renderDroppedFrames 渲染 / $decoderDroppedFrames 解码';
  }

  String get colorLabel {
    final values = <String>[?colorPrimaries, ?transferFunction, ?pixelFormat];
    return values.isEmpty ? '不可用' : values.join(' · ').toUpperCase();
  }

  String toClipboardText({String platform = 'Windows'}) {
    final lines = <String>[
      'PEeK 播放诊断',
      '生成时间: ${sampledAt.toLocal().toIso8601String()}',
      '平台: $platform',
      '服务器: ${serverKind.toUpperCase()} $serverVersion',
      '播放方式: $methodLabel',
      '传输协议: ${sourceProtocol.toUpperCase()}',
      '解码偏好: ${requestedDecodingMode.label}',
      '实际解码: $decoderLabel',
      '视频编码: ${_orUnavailable(videoCodec)}',
      '音频编码: ${_orUnavailable(audioCodec)}',
      '封装格式: ${_orUnavailable(container)}',
      '分辨率: $resolutionLabel',
      '帧率: $frameRateLabel',
      '视频码率: $videoBitrateLabel',
      '音频码率: $audioBitrateLabel',
      '色彩信息: $colorLabel',
      '视频输出: ${_orUnavailable(videoOutput)}',
      '缓存: $cacheLabel${buffering ? '（正在缓冲）' : ''}',
      '丢帧: $droppedFramesLabel',
      '转码原因: ${transcodingReasons.isEmpty ? '服务器未提供' : transcodingReasons.join(', ')}',
      '隐私: 已省略媒体地址、认证信息、用户与媒体标识',
    ];
    return lines.join('\n');
  }

  static String _orUnavailable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? '不可用' : text.toUpperCase();
  }

  static String _formatBitrate(double? bitsPerSecond) {
    if (bitsPerSecond == null) return '不可用';
    if (bitsPerSecond >= 1000000) {
      return '${_trimNumber(bitsPerSecond / 1000000, fractionDigits: 2)} Mbps';
    }
    return '${_trimNumber(bitsPerSecond / 1000, fractionDigits: 0)} Kbps';
  }

  static String _trimNumber(double value, {required int fractionDigits}) {
    final fixed = value.toStringAsFixed(fractionDigits);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
