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
    this.tags = const [],
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
  final List<String> tags;
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
    List<String>? tags,
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
      tags: tags ?? this.tags,
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'overview': overview,
    'productionYear': productionYear,
    'runTimeMs': runTime?.inMilliseconds,
    'imageTag': imageTag,
    'imageUri': imageUri?.toString(),
    'backdropUri': backdropUri?.toString(),
    'imageHeaders': imageHeaders,
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'people': people.map((p) => p.toJson()).toList(),
    'genres': genres,
    'tags': tags,
    'communityRating': communityRating,
    'officialRating': officialRating,
    'tagline': tagline,
    'seriesName': seriesName,
    'indexNumber': indexNumber,
    'parentIndexNumber': parentIndexNumber,
    'parentId': parentId,
    'seriesId': seriesId,
    'collectionType': collectionType,
    'source': source.name,
    'sourcePath': sourcePath,
    'fileSize': fileSize,
    'dateModified': dateModified?.toIso8601String(),
    'played': played,
    'favorite': favorite,
    'resumePositionMs': resumePosition.inMilliseconds,
    'providerIds': providerIds,
    'videoCodec': videoCodec,
    'container': container,
    'width': width,
    'height': height,
    'bitrate': bitrate,
    'mediaSources': mediaSources.map((s) => s.toJson()).toList(),
  };

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind: MediaItemKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => MediaItemKind.movie,
      ),
      overview: json['overview'] as String?,
      productionYear: json['productionYear'] as int?,
      runTime: json['runTimeMs'] != null
          ? Duration(milliseconds: json['runTimeMs'] as int)
          : null,
      imageTag: json['imageTag'] as String?,
      imageUri: json['imageUri'] != null
          ? Uri.tryParse(json['imageUri'] as String)
          : null,
      backdropUri: json['backdropUri'] != null
          ? Uri.tryParse(json['backdropUri'] as String)
          : null,
      imageHeaders: Map<String, String>.from(
        json['imageHeaders'] as Map? ?? const {},
      ),
      chapters: (json['chapters'] as List? ?? const [])
          .map((c) => MediaChapter.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList(),
      people: (json['people'] as List? ?? const [])
          .map((p) => MediaPerson.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      genres: (json['genres'] as List? ?? const []).cast<String>(),
      tags: (json['tags'] as List? ?? const []).cast<String>(),
      communityRating: (json['communityRating'] as num?)?.toDouble(),
      officialRating: json['officialRating'] as String?,
      tagline: json['tagline'] as String?,
      seriesName: json['seriesName'] as String?,
      indexNumber: json['indexNumber'] as int?,
      parentIndexNumber: json['parentIndexNumber'] as int?,
      parentId: json['parentId'] as String?,
      seriesId: json['seriesId'] as String?,
      collectionType: json['collectionType'] as String?,
      source: MediaItemSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => MediaItemSource.remote,
      ),
      sourcePath: json['sourcePath'] as String?,
      fileSize: json['fileSize'] as int?,
      dateModified: json['dateModified'] != null
          ? DateTime.tryParse(json['dateModified'] as String)
          : null,
      played: json['played'] as bool? ?? false,
      favorite: json['favorite'] as bool? ?? false,
      resumePosition: Duration(
        milliseconds: json['resumePositionMs'] as int? ?? 0,
      ),
      providerIds: Map<String, String>.from(
        json['providerIds'] as Map? ?? const {},
      ),
      videoCodec: json['videoCodec'] as String?,
      container: json['container'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      bitrate: json['bitrate'] as int?,
      mediaSources: (json['mediaSources'] as List? ?? const [])
          .map((s) => MediaSourceInfo.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'container': container,
    'fileSize': fileSize,
    'bitrate': bitrate,
    'width': width,
    'height': height,
    'videoCodec': videoCodec,
    'videoRange': videoRange,
    'audioCodec': audioCodec,
    'path': path,
  };

  factory MediaSourceInfo.fromJson(Map<String, dynamic> json) {
    return MediaSourceInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      container: json['container'] as String?,
      fileSize: json['fileSize'] as int?,
      bitrate: json['bitrate'] as int?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      videoCodec: json['videoCodec'] as String?,
      videoRange: json['videoRange'] as String?,
      audioCodec: json['audioCodec'] as String?,
      path: json['path'] as String?,
    );
  }
}

class MediaChapter {
  const MediaChapter({required this.name, required this.startPosition});

  final String name;
  final Duration startPosition;

  Map<String, dynamic> toJson() => {
    'name': name,
    'startPositionMs': startPosition.inMilliseconds,
  };

  factory MediaChapter.fromJson(Map<String, dynamic> json) {
    return MediaChapter(
      name: json['name'] as String? ?? '',
      startPosition: Duration(
        milliseconds: json['startPositionMs'] as int? ?? 0,
      ),
    );
  }
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'role': role,
    'imageUri': imageUri?.toString(),
    'imageHeaders': imageHeaders,
  };

  factory MediaPerson.fromJson(Map<String, dynamic> json) {
    return MediaPerson(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      role: json['role'] as String?,
      imageUri: json['imageUri'] != null
          ? Uri.tryParse(json['imageUri'] as String)
          : null,
      imageHeaders: Map<String, String>.from(
        json['imageHeaders'] as Map? ?? const {},
      ),
    );
  }
}
