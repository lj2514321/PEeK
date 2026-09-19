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

enum MediaItemSource { remote, local }

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
    this.source = MediaItemSource.remote,
    this.sourcePath,
    this.fileSize,
    this.dateModified,
    this.played = false,
    this.favorite = false,
    this.resumePosition = Duration.zero,
    this.providerIds = const {},
    this.videoCodec,
    this.container,
    this.width,
    this.height,
    this.bitrate,
    this.mediaSources = const [],
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
  final MediaItemSource source;
  final String? sourcePath;
  final int? fileSize;
  final DateTime? dateModified;
  final bool played;
  final bool favorite;
  final Duration resumePosition;
  final Map<String, String> providerIds;
  final String? videoCodec;
  final String? container;
  final int? width;
  final int? height;
  final int? bitrate;
  final List<MediaSourceInfo> mediaSources;

  bool get isLocal => source == MediaItemSource.local;

  MediaItem copyWith({
    bool? played,
    bool? favorite,
    Duration? resumePosition,
    Map<String, String>? providerIds,
    String? videoCodec,
    String? container,
    int? width,
    int? height,
    int? bitrate,
    int? fileSize,
    List<MediaSourceInfo>? mediaSources,
    MediaItemSource? source,
    String? sourcePath,
  }) {
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
      source: source ?? this.source,
      sourcePath: sourcePath ?? this.sourcePath,
      fileSize: fileSize ?? this.fileSize,
      dateModified: dateModified,
      played: played ?? this.played,
      favorite: favorite ?? this.favorite,
      resumePosition: resumePosition ?? this.resumePosition,
      providerIds: providerIds ?? this.providerIds,
      videoCodec: videoCodec ?? this.videoCodec,
      container: container ?? this.container,
      width: width ?? this.width,
      height: height ?? this.height,
      bitrate: bitrate ?? this.bitrate,
      mediaSources: mediaSources ?? this.mediaSources,
    );
  }
}

class MediaSourceInfo {
  const MediaSourceInfo({
    required this.id,
    required this.name,
    this.container,
    this.fileSize,
    this.bitrate,
    this.width,
    this.height,
    this.videoCodec,
    this.videoRange,
    this.audioCodec,
    this.path,
  });

  final String id;
  final String name;
  final String? container;
  final int? fileSize;
  final int? bitrate;
  final int? width;
  final int? height;
  final String? videoCodec;
  final String? videoRange;
  final String? audioCodec;
  final String? path;

  String get resolutionLabel {
    if (width != null && height != null) {
      if (width! >= 3840 || height! >= 2160) return '4K';
      if (width! >= 1920 || height! >= 1080) return '1080P';
      if (width! >= 1280 || height! >= 720) return '720P';
      return '${height}P';
    }
    return '';
  }

  String get formattedFileSize {
    final size = fileSize;
    if (size == null || size <= 0) return '';
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(0)} MB';
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
