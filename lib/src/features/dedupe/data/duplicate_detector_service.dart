import 'package:embyplayer/src/features/dedupe/domain/duplicate_media_group.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final duplicateDetectorServiceProvider = Provider<DuplicateDetectorService>((
  ref,
) {
  return const DuplicateDetectorService();
});

class DuplicateDetectorService {
  const DuplicateDetectorService();

  static final _editionPattern = RegExp(
    r'\b(4k|2160p|1080p|720p|480p|uhd|fhd|hd|hdr|hdr10|hdr10\+|dv|dolby\s*vision|remux|extended|unrated|director(?:\x27s)?\s*cut|theatrical|bluray|blu-ray|web-dl|webrip|h\.?264|h\.?265|hevc|av1|x264|x265|aac|dts|ddp5\.1|atmos|uncensored|censored|无码|有码|中文字幕|字幕|hd-c|part\s*\d+|cd\s*\d+)\b',
    caseSensitive: false,
  );

  static final _mediaCodePattern = RegExp(
    r'\b([a-zA-Z]{2,6}[-_]?\d{2,6}|fc2[-_]?(?:ppv)?[-_]?\d+)\b',
    caseSensitive: false,
  );

  static final _bracketPattern = RegExp(r'\[.*?\]|\(.*?\)|【.*?】|（.*?）');
  static final _punctuationPattern = RegExp(r'[^\w\s\u4e00-\u9fa5]+');

  /// Extracts standard movie/video identification code (e.g. SSIS-123, FC2-PPV-123456)
  String? extractMediaCode(String title) {
    final match = _mediaCodePattern.firstMatch(title);
    if (match == null) return null;
    final raw = match.group(0)!;
    return raw.replaceAll('_', '-').toLowerCase();
  }

  /// Normalizes a media title by removing resolution tags, edition markers,
  /// bracketed noise, and special punctuation for comparison.
  String normalizeTitle(String title) {
    var cleaned = title.trim();

    // Remove bracketed parts if they contain quality/edition words
    cleaned = cleaned.replaceAllMapped(_bracketPattern, (match) {
      final inside = match.group(0) ?? '';
      if (_editionPattern.hasMatch(inside)) {
        return '';
      }
      return inside;
    });

    // Remove edition words
    cleaned = cleaned.replaceAll(_editionPattern, '');

    // Replace punctuation with spaces
    cleaned = cleaned.replaceAll(_punctuationPattern, ' ');

    // Normalize whitespaces and lowercase
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

    return cleaned.isEmpty ? title.trim().toLowerCase() : cleaned;
  }

  /// Calculates a quality evaluation score and metrics for a given media item.
  MediaQualityMetrics calculateQualityMetrics(MediaItem item) {
    final title = item.name.toLowerCase();
    final width = item.width ?? 0;
    final height = item.height ?? 0;
    final codec = (item.videoCodec ?? '').toUpperCase();
    final size = item.fileSize;

    // Resolution detection
    final is4K =
        width >= 3840 ||
        height >= 2160 ||
        title.contains('4k') ||
        title.contains('2160');
    final is1080p =
        !is4K && (width >= 1920 || height >= 1080 || title.contains('1080'));
    final is720p =
        !is4K &&
        !is1080p &&
        (width >= 1280 || height >= 720 || title.contains('720'));

    String resolutionLabel;
    int resScore;
    if (is4K) {
      resolutionLabel = '4K UHD';
      resScore = 100;
    } else if (is1080p) {
      resolutionLabel = '1080p FHD';
      resScore = 70;
    } else if (is720p) {
      resolutionLabel = '720p HD';
      resScore = 40;
    } else {
      resolutionLabel = '标清';
      resScore = 20;
    }

    // HDR detection
    final isHDR =
        title.contains('hdr') ||
        title.contains('dv') ||
        title.contains('dolby vision');
    final hdrScore = isHDR ? 25 : 0;

    // Codec evaluation
    String displayCodec;
    int codecScore = 5;
    if (codec.contains('AV1') || title.contains('av1')) {
      displayCodec = 'AV1';
      codecScore = 15;
    } else if (codec.contains('HEVC') ||
        codec.contains('H265') ||
        title.contains('hevc') ||
        title.contains('x265') ||
        title.contains('h.265')) {
      displayCodec = 'HEVC';
      codecScore = 12;
    } else if (codec.contains('H264') ||
        title.contains('x264') ||
        title.contains('h.264')) {
      displayCodec = 'H.264';
      codecScore = 8;
    } else if (codec.isNotEmpty) {
      displayCodec = codec;
    } else {
      displayCodec = '标准视频';
    }

    // Audio format detection from title
    String audioFormat;
    int audioScore = 5;
    if (title.contains('atmos') || title.contains('truehd')) {
      audioFormat = 'Dolby Atmos';
      audioScore = 20;
    } else if (title.contains('dts-hd') || title.contains('dts:x')) {
      audioFormat = 'DTS:X / DTS-HD';
      audioScore = 18;
    } else if (title.contains('5.1') || title.contains('7.1')) {
      audioFormat = '多声道 5.1/7.1';
      audioScore = 12;
    } else {
      audioFormat = '立体声';
    }

    // File size bonus (up to 30 points)
    var sizeScore = 0;
    if (size != null && size > 0) {
      final gb = size / (1024 * 1024 * 1024);
      sizeScore = (gb * 2).clamp(0, 30).round();
    }

    // User preference affinity (played or favorite)
    final historyScore = (item.played ? 10 : 0) + (item.favorite ? 15 : 0);

    final totalScore =
        resScore +
        hdrScore +
        codecScore +
        audioScore +
        sizeScore +
        historyScore;

    // Advantage tags for UI
    final tags = <String>[];
    if (is4K) tags.add('4K超高清');
    if (isHDR) tags.add('HDR高动态');
    if (displayCodec == 'HEVC' || displayCodec == 'AV1') tags.add('高能效编码');
    if (audioScore >= 18) tags.add('高清音轨');
    if (item.favorite) tags.add('已收藏');
    if (item.played) tags.add('已观看');

    return MediaQualityMetrics(
      resolutionLabel: resolutionLabel,
      is4K: is4K,
      isHDR: isHDR,
      videoCodec: displayCodec,
      audioFormat: audioFormat,
      fileSize: size,
      qualityScore: totalScore,
      advantageTags: tags,
    );
  }

  /// Scans a collection of [MediaItem]s and identifies duplicate groups
  /// using graph-connected components across provider IDs, media codes,
  /// identical cover image tags, matching cast, matching runtime, and titles.
  List<DuplicateMediaGroup> findDuplicates(
    List<MediaItem> items, {
    Set<String> ignoredGroupIds = const {},
  }) {
    // Exclude folders and persons
    final mediaList = items
        .where((item) {
          return item.kind != MediaItemKind.folder &&
              item.kind != MediaItemKind.person;
        })
        .toList(growable: false);

    final n = mediaList.length;
    if (n < 2) return const [];

    // Disjoint-set union (DSU) for clustering
    final parent = List<int>.generate(n, (i) => i);
    final edgeReasons = <int, DuplicateMatchReason>{};
    final edgeDetails = <int, String>{};

    int find(int i) {
      if (parent[i] == i) return i;
      return parent[i] = find(parent[i]);
    }

    void union(int i, int j, DuplicateMatchReason reason, String detail) {
      final rootI = find(i);
      final rootJ = find(j);
      if (rootI != rootJ) {
        parent[rootI] = rootJ;
        // Keep the highest-priority reason
        final existingReason = edgeReasons[rootJ];
        if (existingReason == null || reason.index < existingReason.index) {
          edgeReasons[rootJ] = reason;
          edgeDetails[rootJ] = detail;
        }
      }
    }

    // 1. Group by TMDb / IMDb Provider IDs
    final tmdbMap = <String, int>{};
    final imdbMap = <String, int>{};

    // 2. Group by Media Identification Code (e.g. SSIS-123)
    final codeMap = <String, int>{};

    // 3. Group by Image Tag (Same Cover/Poster)
    final imageTagMap = <String, int>{};

    // 4. Group by Episode Key
    final episodeMap = <String, int>{};

    // 5. Group by Normalized Clean Title
    final titleMap = <String, List<int>>{};

    for (var i = 0; i < n; i++) {
      final item = mediaList[i];

      // Provider IDs
      final tmdb = item.providerIds['Tmdb'];
      if (tmdb != null && tmdb.isNotEmpty) {
        if (tmdbMap.containsKey(tmdb)) {
          union(
            i,
            tmdbMap[tmdb]!,
            DuplicateMatchReason.providerId,
            'TMDb ID: $tmdb',
          );
        } else {
          tmdbMap[tmdb] = i;
        }
      }

      final imdb = item.providerIds['Imdb'];
      if (imdb != null && imdb.isNotEmpty) {
        if (imdbMap.containsKey(imdb)) {
          union(
            i,
            imdbMap[imdb]!,
            DuplicateMatchReason.providerId,
            'IMDb ID: $imdb',
          );
        } else {
          imdbMap[imdb] = i;
        }
      }

      // Media Code
      final code = extractMediaCode(item.name);
      if (code != null && code.isNotEmpty) {
        if (codeMap.containsKey(code)) {
          union(
            i,
            codeMap[code]!,
            DuplicateMatchReason.mediaCode,
            '识别码: ${code.toUpperCase()}',
          );
        } else {
          codeMap[code] = i;
        }
      }

      // Image Tag (Same Cover Poster)
      final tag = item.imageTag;
      if (tag != null && tag.isNotEmpty) {
        if (imageTagMap.containsKey(tag)) {
          union(i, imageTagMap[tag]!, DuplicateMatchReason.imageTag, '相同封面海报');
        } else {
          imageTagMap[tag] = i;
        }
      }

      // Episode Key
      if (item.kind == MediaItemKind.episode &&
          item.indexNumber != null &&
          (item.seriesName != null || item.seriesId != null)) {
        final seriesKey = (item.seriesName ?? item.seriesId ?? '')
            .toLowerCase()
            .trim();
        final season = item.parentIndexNumber ?? 1;
        final ep = item.indexNumber!;
        final epKey = '$seriesKey:s$season:e$ep';
        if (episodeMap.containsKey(epKey)) {
          union(
            i,
            episodeMap[epKey]!,
            DuplicateMatchReason.episode,
            '同一剧集单集 (S${season}E$ep)',
          );
        } else {
          episodeMap[epKey] = i;
        }
      }

      // Clean Title
      final cleanTitle = normalizeTitle(item.name);
      if (cleanTitle.isNotEmpty) {
        titleMap.putIfAbsent(cleanTitle, () => []).add(i);
      }
    }

    // 6. Inspect Clean Title groups:
    // Match by exact title, or title + cast, title + runtime, title + year
    for (final entry in titleMap.entries) {
      final indices = entry.value;
      if (indices.length < 2) continue;

      for (var a = 0; a < indices.length - 1; a++) {
        for (var b = a + 1; b < indices.length; b++) {
          final idxA = indices[a];
          final idxB = indices[b];
          final itemA = mediaList[idxA];
          final itemB = mediaList[idxB];

          // Check Cast overlap
          final castA = itemA.people
              .map((p) => p.name.trim().toLowerCase())
              .where((n) => n.isNotEmpty)
              .toSet();
          final castB = itemB.people
              .map((p) => p.name.trim().toLowerCase())
              .where((n) => n.isNotEmpty)
              .toSet();
          final sharedCast = castA.intersection(castB);

          if (sharedCast.isNotEmpty) {
            final actorName = itemA.people
                .firstWhere(
                  (p) => sharedCast.contains(p.name.trim().toLowerCase()),
                )
                .name;
            union(
              idxA,
              idxB,
              DuplicateMatchReason.titleAndCast,
              '同名且主演阵容一致 ($actorName 等)',
            );
            continue;
          }

          // Check Runtime similarity (within 3 minutes or 5%)
          if (itemA.runTime != null && itemB.runTime != null) {
            final diffSecs =
                (itemA.runTime!.inSeconds - itemB.runTime!.inSeconds).abs();
            if (diffSecs <= 180 ||
                diffSecs / (itemA.runTime!.inSeconds + 1) < 0.05) {
              union(
                idxA,
                idxB,
                DuplicateMatchReason.titleAndRuntime,
                '同名且片长一致 (~${itemA.runTime!.inMinutes}分钟)',
              );
              continue;
            }
          }

          // Check Year match
          if (itemA.productionYear != null && itemB.productionYear != null) {
            final yearDiff = (itemA.productionYear! - itemB.productionYear!)
                .abs();
            if (yearDiff <= 1) {
              union(
                idxA,
                idxB,
                DuplicateMatchReason.titleAndYear,
                '规范化标题与年份一致 (${itemA.productionYear})',
              );
              continue;
            }
          }

          // Default fallback: Same Title
          union(idxA, idxB, DuplicateMatchReason.exactTitle, '作品名称完全一致');
        }
      }
    }

    // 7. Extract clusters from DSU
    final clusterMap = <int, List<MediaItem>>{};
    for (var i = 0; i < n; i++) {
      final root = find(i);
      clusterMap.putIfAbsent(root, () => []).add(mediaList[i]);
    }

    final resultGroups = <DuplicateMediaGroup>[];

    for (final entry in clusterMap.entries) {
      final root = entry.key;
      final groupItems = entry.value;

      if (groupItems.length < 2) continue;

      final matchReason = edgeReasons[root] ?? DuplicateMatchReason.exactTitle;
      final matchDetail = edgeDetails[root] ?? matchReason.label;

      // Group ID for persistent ignore whitelist
      final firstItem = groupItems.first;
      final tmdb = firstItem.providerIds['Tmdb'];
      final code = extractMediaCode(firstItem.name);
      final groupId = tmdb != null && tmdb.isNotEmpty
          ? 'tmdb:$tmdb'
          : (code != null && code.isNotEmpty
                ? 'code:$code'
                : (firstItem.imageTag != null && firstItem.imageTag!.isNotEmpty
                      ? 'img:${firstItem.imageTag}'
                      : 'title:${normalizeTitle(firstItem.name)}'));

      if (ignoredGroupIds.contains(groupId)) continue;

      // Compute quality metrics for each item in the group
      final scoredItems = groupItems.map((item) {
        final metrics = calculateQualityMetrics(item);
        return (item: item, metrics: metrics);
      }).toList();

      // Sort descending by qualityScore
      scoredItems.sort(
        (a, b) => b.metrics.qualityScore.compareTo(a.metrics.qualityScore),
      );

      final bestItem = scoredItems.first;
      final recommendedKeepId = bestItem.item.id;

      final defaultDeleteIds = scoredItems
          .where((i) => i.item.id != recommendedKeepId)
          .map((i) => i.item.id)
          .toSet();

      final duplicateItems = scoredItems
          .map((scored) {
            return DuplicateGroupItem(
              item: scored.item,
              metrics: scored.metrics,
              isRecommendedKeep: scored.item.id == recommendedKeepId,
            );
          })
          .toList(growable: false);

      resultGroups.add(
        DuplicateMediaGroup(
          id: groupId,
          title: groupItems.first.name,
          productionYear: groupItems.first.productionYear,
          matchReason: matchReason,
          matchDetail: matchDetail,
          items: duplicateItems,
          recommendedKeepId: recommendedKeepId,
          selectedDeleteIds: defaultDeleteIds,
        ),
      );
    }

    // Sort groups by potential savings descending
    resultGroups.sort(
      (a, b) => b.potentialSavingsBytes.compareTo(a.potentialSavingsBytes),
    );

    return resultGroups;
  }
}
