import 'package:embyplayer/src/core/domain/media_item.dart';

enum PlaybackMethod { directPlay, directStream, transcode }

enum PlaybackTrackKind { audio, subtitle }

class PlaybackTrackInfo {
  const PlaybackTrackInfo({
    required this.index,
    required this.kind,
    required this.label,
    this.title,
    this.language,
    this.codec,
    this.channels,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    this.isText = false,
    this.deliveryUri,
  });

  final int index;
  final PlaybackTrackKind kind;
  final String label;
  final String? title;
  final String? language;
  final String? codec;
  final String? channels;
  final bool isDefault;
  final bool isForced;
  final bool isExternal;
  final bool isText;
  final Uri? deliveryUri;

  Map<String, dynamic> toJson() => {
    'index': index,
    'kind': kind.name,
    'label': label,
    'title': title,
    'language': language,
    'codec': codec,
    'channels': channels,
    'isDefault': isDefault,
    'isForced': isForced,
    'isExternal': isExternal,
    'isText': isText,
    'deliveryUri': deliveryUri?.toString(),
  };

  factory PlaybackTrackInfo.fromJson(Map<String, dynamic> json) {
    return PlaybackTrackInfo(
      index: json['index'] as int? ?? 0,
      kind: PlaybackTrackKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => PlaybackTrackKind.audio,
      ),
      label: json['label'] as String? ?? '',
      title: json['title'] as String?,
      language: json['language'] as String?,
      codec: json['codec'] as String?,
      channels: json['channels'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
      isForced: json['isForced'] as bool? ?? false,
      isExternal: json['isExternal'] as bool? ?? false,
      isText: json['isText'] as bool? ?? false,
      deliveryUri: json['deliveryUri'] != null
          ? Uri.tryParse(json['deliveryUri'] as String)
          : null,
    );
  }
}

class PlaybackPlan {
  const PlaybackPlan({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.streamUri,
    required this.method,
    this.httpHeaders = const {},
    this.startPosition = Duration.zero,
    this.duration,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.chapters = const [],
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.transcodingReasons = const [],
  });

  final String itemId;
  final String mediaSourceId;
  final String playSessionId;
  final Uri streamUri;
  final PlaybackMethod method;
  final Map<String, String> httpHeaders;
  final Duration startPosition;
  final Duration? duration;
  final List<PlaybackTrackInfo> audioTracks;
  final List<PlaybackTrackInfo> subtitleTracks;
  final List<MediaChapter> chapters;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final List<String> transcodingReasons;

  PlaybackPlan copyWith({
    String? itemId,
    String? mediaSourceId,
    String? playSessionId,
    Uri? streamUri,
    PlaybackMethod? method,
    Map<String, String>? httpHeaders,
    Duration? startPosition,
    Duration? duration,
    List<PlaybackTrackInfo>? audioTracks,
    List<PlaybackTrackInfo>? subtitleTracks,
    List<MediaChapter>? chapters,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    List<String>? transcodingReasons,
  }) {
    return PlaybackPlan(
      itemId: itemId ?? this.itemId,
      mediaSourceId: mediaSourceId ?? this.mediaSourceId,
      playSessionId: playSessionId ?? this.playSessionId,
      streamUri: streamUri ?? this.streamUri,
      method: method ?? this.method,
      httpHeaders: httpHeaders ?? this.httpHeaders,
      startPosition: startPosition ?? this.startPosition,
      duration: duration ?? this.duration,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      chapters: chapters ?? this.chapters,
      audioStreamIndex: audioStreamIndex ?? this.audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex ?? this.subtitleStreamIndex,
      transcodingReasons: transcodingReasons ?? this.transcodingReasons,
    );
  }

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'mediaSourceId': mediaSourceId,
    'playSessionId': playSessionId,
    'streamUri': streamUri.toString(),
    'method': method.name,
    'httpHeaders': httpHeaders,
    'startPositionMs': startPosition.inMilliseconds,
    'durationMs': duration?.inMilliseconds,
    'audioTracks': audioTracks.map((t) => t.toJson()).toList(),
    'subtitleTracks': subtitleTracks.map((t) => t.toJson()).toList(),
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'audioStreamIndex': audioStreamIndex,
    'subtitleStreamIndex': subtitleStreamIndex,
    'transcodingReasons': transcodingReasons,
  };

  factory PlaybackPlan.fromJson(Map<String, dynamic> json) {
    return PlaybackPlan(
      itemId: json['itemId'] as String? ?? '',
      mediaSourceId: json['mediaSourceId'] as String? ?? '',
      playSessionId: json['playSessionId'] as String? ?? '',
      streamUri: Uri.parse(json['streamUri'] as String? ?? ''),
      method: PlaybackMethod.values.firstWhere(
        (m) => m.name == json['method'],
        orElse: () => PlaybackMethod.directPlay,
      ),
      httpHeaders: Map<String, String>.from(
        json['httpHeaders'] as Map? ?? const {},
      ),
      startPosition: Duration(
        milliseconds: json['startPositionMs'] as int? ?? 0,
      ),
      duration: json['durationMs'] != null
          ? Duration(milliseconds: json['durationMs'] as int)
          : null,
      audioTracks: (json['audioTracks'] as List? ?? const [])
          .map(
            (t) =>
                PlaybackTrackInfo.fromJson(Map<String, dynamic>.from(t as Map)),
          )
          .toList(),
      subtitleTracks: (json['subtitleTracks'] as List? ?? const [])
          .map(
            (t) =>
                PlaybackTrackInfo.fromJson(Map<String, dynamic>.from(t as Map)),
          )
          .toList(),
      chapters: (json['chapters'] as List? ?? const [])
          .map(
            (c) => MediaChapter.fromJson(Map<String, dynamic>.from(c as Map)),
          )
          .toList(),
      audioStreamIndex: json['audioStreamIndex'] as int?,
      subtitleStreamIndex: json['subtitleStreamIndex'] as int?,
      transcodingReasons: (json['transcodingReasons'] as List? ?? const [])
          .cast<String>(),
    );
  }
}

class PlaybackSessionSnapshot {
  const PlaybackSessionSnapshot({
    required this.plan,
    required this.position,
    required this.isPaused,
    required this.volume,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.subtitlesDisabled = false,
    this.playbackRate = 1,
    this.subtitleOffset = Duration.zero,
  });

  final PlaybackPlan plan;
  final Duration position;
  final bool isPaused;
  final double volume;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final bool subtitlesDisabled;
  final double playbackRate;
  final Duration subtitleOffset;
}
