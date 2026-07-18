enum PlaybackMethod { directPlay, directStream, transcode }

class PlaybackPlan {
  const PlaybackPlan({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.streamUri,
    required this.method,
    this.httpHeaders = const {},
    this.startPosition = Duration.zero,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
  });

  final String itemId;
  final String mediaSourceId;
  final String playSessionId;
  final Uri streamUri;
  final PlaybackMethod method;
  final Map<String, String> httpHeaders;
  final Duration startPosition;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
}

class PlaybackSessionSnapshot {
  const PlaybackSessionSnapshot({
    required this.plan,
    required this.position,
    required this.isPaused,
    required this.volume,
  });

  final PlaybackPlan plan;
  final Duration position;
  final bool isPaused;
  final double volume;
}
