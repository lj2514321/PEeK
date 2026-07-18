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
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final List<String> transcodingReasons;
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
  });

  final PlaybackPlan plan;
  final Duration position;
  final bool isPaused;
  final double volume;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final bool subtitlesDisabled;
  final double playbackRate;
}
