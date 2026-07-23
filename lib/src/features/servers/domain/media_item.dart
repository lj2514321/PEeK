enum MediaItemKind {
  movie,
  series,
  season,
  episode,
  video,
  audio,
  person,
  folder,
}

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
    this.chapters = const [],
    this.people = const [],
    this.genres = const [],
    this.communityRating,
    this.officialRating,
    this.tagline,
    this.seriesName,
    this.indexNumber,
    this.parentIndexNumber,
    this.parentId,
    this.seriesId,
    this.collectionType,
    this.played = false,
    this.favorite = false,
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
  final List<MediaChapter> chapters;
  final List<MediaPerson> people;
  final List<String> genres;
  final double? communityRating;
  final String? officialRating;
  final String? tagline;
  final String? seriesName;
  final int? indexNumber;
  final int? parentIndexNumber;
  final String? parentId;
  final String? seriesId;
  final String? collectionType;
  final bool played;
  final bool favorite;
  final Duration resumePosition;

  MediaItem copyWith({bool? played, bool? favorite, Duration? resumePosition}) {
    return MediaItem(
      id: id,
      name: name,
      kind: kind,
      overview: overview,
      productionYear: productionYear,
      runTime: runTime,
      imageTag: imageTag,
      imageUri: imageUri,
      backdropUri: backdropUri,
      imageHeaders: imageHeaders,
      chapters: chapters,
      people: people,
      genres: genres,
      communityRating: communityRating,
      officialRating: officialRating,
      tagline: tagline,
      seriesName: seriesName,
      indexNumber: indexNumber,
      parentIndexNumber: parentIndexNumber,
      parentId: parentId,
      seriesId: seriesId,
      collectionType: collectionType,
      played: played ?? this.played,
      favorite: favorite ?? this.favorite,
      resumePosition: resumePosition ?? this.resumePosition,
    );
  }
}

class MediaChapter {
  const MediaChapter({required this.name, required this.startPosition});

  final String name;
  final Duration startPosition;
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
