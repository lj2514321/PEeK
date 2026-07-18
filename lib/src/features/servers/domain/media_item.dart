enum MediaItemKind { movie, series, season, episode, video, audio, folder }

class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.kind,
    this.overview,
    this.productionYear,
    this.runTime,
    this.imageTag,
    this.imageUri,
    this.backdropUri,
    this.imageHeaders = const {},
    this.people = const [],
    this.genres = const [],
    this.communityRating,
    this.officialRating,
    this.tagline,
    this.seriesName,
    this.indexNumber,
    this.parentIndexNumber,
    this.parentId,
    this.played = false,
    this.resumePosition = Duration.zero,
  });

  final String id;
  final String name;
  final MediaItemKind kind;
  final String? overview;
  final int? productionYear;
  final Duration? runTime;
  final String? imageTag;
  final Uri? imageUri;
  final Uri? backdropUri;
  final Map<String, String> imageHeaders;
  final List<MediaPerson> people;
  final List<String> genres;
  final double? communityRating;
  final String? officialRating;
  final String? tagline;
  final String? seriesName;
  final int? indexNumber;
  final int? parentIndexNumber;
  final String? parentId;
  final bool played;
  final Duration resumePosition;
}

class MediaPerson {
  const MediaPerson({
    required this.id,
    required this.name,
    required this.type,
    this.role,
    this.imageUri,
    this.imageHeaders = const {},
  });

  final String id;
  final String name;
  final String type;
  final String? role;
  final Uri? imageUri;
  final Map<String, String> imageHeaders;
}
