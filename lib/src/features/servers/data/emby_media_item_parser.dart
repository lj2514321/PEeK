import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

/// Clean parser class for transforming Jellyfin/Emby DTOs to MediaItem objects.
class EmbyMediaItemParser {
  const EmbyMediaItemParser._();

  static MediaItem parseItem(Map<String, dynamic> data, AuthenticatedServer account) {
    final id = readString(data, 'Id');
    final imageTags = data['ImageTags'];
    final imageTag = imageTags is Map ? imageTags['Primary'] : null;
    final backdropTags = data['BackdropImageTags'];
    final backdropTag = backdropTags is List && backdropTags.isNotEmpty
        ? backdropTags.first
        : null;
    final primaryImageItemId = readString(
      data,
      'PrimaryImageItemId',
      fallback: id,
    );
    final userData = data['UserData'];
    final runTimeTicks = readInt(data['RunTimeTicks']);
    final resumeTicks = userData is Map
        ? readInt(userData['PlaybackPositionTicks'])
        : null;
    final played = userData is Map && userData['Played'] == true;
    final favorite = userData is Map && userData['IsFavorite'] == true;

    final rawProviderIds = data['ProviderIds'];
    final providerIds = <String, String>{};
    if (rawProviderIds is Map) {
      for (final entry in rawProviderIds.entries) {
        if (entry.value != null && entry.value.toString().isNotEmpty) {
          providerIds[entry.key.toString()] = entry.value.toString();
        }
      }
    }

    final mediaSources = data['MediaSources'];
    final firstSource = (mediaSources is List && mediaSources.isNotEmpty && mediaSources.first is Map)
        ? mediaSources.first as Map<String, dynamic>
        : null;
    final mediaStreams = (firstSource != null && firstSource['MediaStreams'] is List)
        ? firstSource['MediaStreams'] as List
        : (data['MediaStreams'] is List ? data['MediaStreams'] as List : const []);
    final videoStream = mediaStreams.firstWhere(
      (s) => s is Map && s['Type'] == 'Video',
      orElse: () => null,
    ) as Map<String, dynamic>?;

    final width = readInt(videoStream?['Width']) ?? readInt(data['Width']);
    final height = readInt(videoStream?['Height']) ?? readInt(data['Height']);
    final videoCodec = readNullableString(videoStream, 'Codec') ?? readNullableString(data, 'VideoCodec');
    final container = readNullableString(firstSource, 'Container') ?? readNullableString(data, 'Container');
    final bitrate = readInt(firstSource?['Bitrate']) ?? readInt(data['Bitrate']);
    final sourceSize = readInt(firstSource?['Size']);

    return MediaItem(
      id: id,
      name: readString(data, 'Name'),
      kind: readKind(readString(data, 'Type')),
      overview: readNullableString(data, 'Overview'),
      productionYear: readInt(data['ProductionYear']),
      runTime: runTimeTicks == null
          ? null
          : Duration(microseconds: runTimeTicks ~/ 10),
      imageTag: imageTag is String ? imageTag : null,
      imageUri: imageTag is String && primaryImageItemId.isNotEmpty
          ? imageUri(account.server.apiBaseUri, primaryImageItemId, imageTag)
          : null,
      backdropUri: backdropTag is String
          ? imageUri(
              account.server.apiBaseUri,
              id,
              backdropTag,
              type: 'Backdrop',
              index: 0,
              maxWidth: 1600,
            )
          : null,
      imageHeaders: authHeaders(account.accessToken),
      chapters: readChapters(data['Chapters']),
      people: readPeople(data['People'], account),
      genres: readStringList(data['Genres']),
      communityRating: readDouble(data['CommunityRating']),
      officialRating: readNullableString(data, 'OfficialRating'),
      tagline:
          readNullableString(data, 'Tagline') ??
          readFirstString(data['Taglines']),
      seriesName: readNullableString(data, 'SeriesName'),
      indexNumber: readInt(data['IndexNumber']),
      parentIndexNumber: readInt(data['ParentIndexNumber']),
      parentId: readNullableString(data, 'ParentId'),
      seriesId: readNullableString(data, 'SeriesId'),
      collectionType: readNullableString(data, 'CollectionType'),
      fileSize: sourceSize,
      played: played,
      favorite: favorite,
      resumePosition: resumeTicks == null
          ? Duration.zero
          : Duration(microseconds: resumeTicks ~/ 10),
      providerIds: providerIds,
      videoCodec: videoCodec,
      container: container,
      width: width,
      height: height,
      bitrate: bitrate,
    );
  }

  static MediaItem parseSearchHint(
    Map<String, dynamic> data,
    AuthenticatedServer account,
  ) {
    final id = readString(data, 'Id', fallback: readString(data, 'ItemId'));
    final primaryTag = readNullableString(data, 'PrimaryImageTag');
    final thumbTag = readNullableString(data, 'ThumbImageTag');
    final imageTag = primaryTag ?? thumbTag;
    final imageItemId = primaryTag != null
        ? readString(data, 'PrimaryImageItemId', fallback: id)
        : readString(data, 'ThumbImageItemId', fallback: id);
    final backdropTag = readNullableString(data, 'BackdropImageTag');
    final backdropItemId = readString(
      data,
      'BackdropImageItemId',
      fallback: id,
    );
    final runTimeTicks = readInt(data['RunTimeTicks']);
    return MediaItem(
      id: id,
      name: readString(data, 'Name'),
      kind: readKind(readString(data, 'Type')),
      productionYear: readInt(data['ProductionYear']),
      runTime: runTimeTicks == null
          ? null
          : Duration(microseconds: runTimeTicks ~/ 10),
      imageTag: imageTag,
      imageUri: imageTag == null || imageItemId.isEmpty
          ? null
          : imageUri(account.server.apiBaseUri, imageItemId, imageTag),
      backdropUri: backdropTag == null || backdropItemId.isEmpty
          ? null
          : imageUri(
              account.server.apiBaseUri,
              backdropItemId,
              backdropTag,
              type: 'Backdrop',
              index: 0,
              maxWidth: 1600,
            ),
      imageHeaders: authHeaders(account.accessToken),
      seriesName: readNullableString(data, 'Series'),
      indexNumber: readInt(data['IndexNumber']),
      parentIndexNumber: readInt(data['ParentIndexNumber']),
      seriesId: readNullableString(data, 'SeriesId'),
    );
  }

  static Uri imageUri(
    Uri base,
    String itemId,
    String tag, {
    String type = 'Primary',
    int? index,
    int maxWidth = 480,
  }) {
    final path = index == null
        ? 'Items/$itemId/Images/$type'
        : 'Items/$itemId/Images/$type/$index';
    return appendPath(base, path).replace(
      queryParameters: {'tag': tag, 'maxWidth': '$maxWidth', 'quality': '90'},
    );
  }

  static Uri appendPath(Uri base, String relativePath) {
    final cleanRelative = relativePath.trim().replaceAll(RegExp(r'^/+'), '');
    final basePath = base.path.replaceAll(RegExp(r'/+$'), '');
    final mergedPath = basePath.isEmpty
        ? '/$cleanRelative'
        : '$basePath/$cleanRelative';
    return base.replace(path: mergedPath);
  }

  static Map<String, String> authHeaders(String token) {
    return {'X-Emby-Token': token, 'Accept': 'application/json'};
  }

  static List<MediaChapter> readChapters(Object? value) {
    if (value is! List) return const [];
    final chapters =
        value
            .whereType<Map>()
            .map((chapter) {
              final ticks = readInt(chapter['StartPositionTicks']);
              if (ticks == null || ticks < 0) return null;
              final rawName = chapter['Name'];
              final name = rawName is String ? rawName.trim() : '';
              return MediaChapter(
                name: name.isEmpty ? '章节' : name,
                startPosition: Duration(microseconds: ticks ~/ 10),
              );
            })
            .whereType<MediaChapter>()
            .toList(growable: true)
          ..sort((a, b) => a.startPosition.compareTo(b.startPosition));
    return List.unmodifiable(chapters);
  }

  static List<MediaPerson> readPeople(
    Object? value,
    AuthenticatedServer account,
  ) {
    if (value is! List) return const [];
    final people =
        value
            .whereType<Map>()
            .map((person) {
              final id = readString(person, 'Id');
              final name = readString(person, 'Name');
              if (id.isEmpty && name.isEmpty) return null;
              final primaryTag = person['PrimaryImageTag'];
              final tag = primaryTag is String ? primaryTag : null;
              final role = readNullableString(person, 'Role');
              final type = readNullableString(person, 'Type') ?? 'Actor';

              return MediaPerson(
                id: id,
                name: name.isEmpty ? (role ?? '未知人员') : name,
                type: type,
                role: role,
                imageUri: tag == null || id.isEmpty
                    ? null
                    : imageUri(account.server.apiBaseUri, id, tag),
                imageHeaders: authHeaders(account.accessToken),
              );
            })
            .whereType<MediaPerson>()
            .toList(growable: false);
    return List.unmodifiable(people);
  }

  static MediaItemKind readKind(String type) {
    return switch (type.toLowerCase()) {
      'movie' => MediaItemKind.movie,
      'series' => MediaItemKind.series,
      'season' => MediaItemKind.season,
      'episode' => MediaItemKind.episode,
      'video' => MediaItemKind.video,
      'audio' => MediaItemKind.audio,
      'person' => MediaItemKind.person,
      'folder' ||
      'userview' ||
      'collectionfolder' ||
      'boxset' => MediaItemKind.folder,
      _ => MediaItemKind.video,
    };
  }

  static String readString(
    Map<dynamic, dynamic> data,
    String key, {
    String fallback = '',
  }) {
    final value = data[key];
    if (value is String) return value.trim();
    if (value != null) return value.toString().trim();
    return fallback;
  }

  static String? readNullableString(Map<dynamic, dynamic>? data, String key) {
    if (data == null) return null;
    final value = data[key];
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  static String? readFirstString(Object? value) {
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is String && first.trim().isNotEmpty) {
        return first.trim();
      }
    }
    return null;
  }

  static List<String> readStringList(Object? value) {
    if (value is! List) return const [];
    final items =
        value
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
    return List.unmodifiable(items);
  }

  static int? readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double? readDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }
}
