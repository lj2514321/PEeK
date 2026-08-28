import 'package:embyplayer/src/features/dedupe/domain/duplicate_media_group.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final duplicateDetectorServiceProvider = Provider<DuplicateDetectorService>((ref) {
  return const DuplicateDetectorService();
});

class DuplicateDetectorService {
  const DuplicateDetectorService();

  static final _editionPattern = RegExp(
    r'\b(4k|2160p|1080p|720p|480p|uhd|fhd|hd|hdr|hdr10|hdr10\+|dv|dolby\s*vision|remux|extended|unrated|director(?:\x27s)?\s*cut|theatrical|bluray|blu-ray|web-dl|webrip|h\.?264|h\.?265|hevc|av1|x264|x265|aac|dts|ddp5\.1|atmos)\b',
    caseSensitive: false,
  );

  static final _bracketPattern = RegExp(r'\[.*?\]|\(.*?\)|【.*?】|（.*?）');
  static final _punctuationPattern = RegExp(r'[^\w\s\u4e00-\u9fa5]+');

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
    final is4K = width >= 3840 ||
        height >= 2160 ||
        title.contains('4k') ||
        title.contains('2160');
    final is1080p = !is4K &&
        (width >= 1920 || height >= 1080 || title.contains('1080'));
    final is720p = !is4K &&
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
    final isHDR = title.contains('hdr') ||
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

    final totalScore = resScore + hdrScore + codecScore + audioScore + sizeScore + historyScore;

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

  /// Scans a collection of [MediaItem]s and identifies duplicate groups.
  List<DuplicateMediaGroup> findDuplicates(
    List<MediaItem> items, {
    Set<String> ignoredGroupIds = const {},
  }) {
    // Exclude folders and persons
    final mediaList = items.where((item) {
      return item.kind != MediaItemKind.folder &&
          item.kind != MediaItemKind.person;
    }).toList(growable: false);

    final groupedByPrimaryId = <String, List<MediaItem>>{};
    final itemAssignedKeys = <String, String>{};

    for (final item in mediaList) {
      // 1. Check Provider ID (TMDb, IMDb)
      final tmdb = item.providerIds['Tmdb'];
      final imdb = item.providerIds['Imdb'];
      if (tmdb != null && tmdb.isNotEmpty) {
        final key = 'tmdb:$tmdb';
        groupedByPrimaryId.putIfAbsent(key, () => []).add(item);
        itemAssignedKeys[item.id] = key;
        continue;
      }
      if (imdb != null && imdb.isNotEmpty) {
        final key = 'imdb:$imdb';
        groupedByPrimaryId.putIfAbsent(key, () => []).add(item);
        itemAssignedKeys[item.id] = key;
        continue;
      }

      // 2. Check Episode matching (same show + season + episode)
      if (item.kind == MediaItemKind.episode &&
          item.indexNumber != null &&
          (item.seriesName != null || item.seriesId != null)) {
        final seriesKey = (item.seriesName ?? item.seriesId ?? '').toLowerCase().trim();
        final season = item.parentIndexNumber ?? 1;
        final ep = item.indexNumber!;
        final key = 'episode:$seriesKey:s$season:e$ep';
        groupedByPrimaryId.putIfAbsent(key, () => []).add(item);
        itemAssignedKeys[item.id] = key;
        continue;
      }

      // 3. Fallback: Normalized Title + Year
      final normTitle = normalizeTitle(item.name);
      if (normTitle.isNotEmpty) {
        final year = item.productionYear?.toString() ?? 'unknown';
        final key = 'title:$normTitle:$year';
        groupedByPrimaryId.putIfAbsent(key, () => []).add(item);
        itemAssignedKeys[item.id] = key;
      }
    }

    final resultGroups = <DuplicateMediaGroup>[];

    for (final entry in groupedByPrimaryId.entries) {
      final groupKey = entry.key;
      final groupItems = entry.value;

      // Only groups with 2 or more copies are duplicates
      if (groupItems.length < 2) continue;

      // Skip ignored whitelist groups
      if (ignoredGroupIds.contains(groupKey)) continue;

      // Determine match reason and detail
      DuplicateMatchReason matchReason;
      String matchDetail;

      if (groupKey.startsWith('tmdb:') || groupKey.startsWith('imdb:')) {
        matchReason = DuplicateMatchReason.providerId;
        final idVal = groupKey.split(':').last;
        matchDetail = groupKey.startsWith('tmdb:') ? 'TMDb ID: $idVal' : 'IMDb ID: $idVal';
      } else if (groupKey.startsWith('episode:')) {
        matchReason = DuplicateMatchReason.episode;
        final parts = groupKey.split(':');
        final season = parts.length > 2 ? parts[2].toUpperCase() : '';
        final ep = parts.length > 3 ? parts[3].toUpperCase() : '';
        matchDetail = '同一剧集单集 ($season$ep)';
      } else {
        matchReason = DuplicateMatchReason.titleAndYear;
        final year = groupItems.first.productionYear;
        matchDetail = year != null ? '规范化标题相同 ($year年)' : '规范化标题相同';
      }

      // Compute quality metrics for each item in the group
      final scoredItems = groupItems.map((item) {
        final metrics = calculateQualityMetrics(item);
        return (item: item, metrics: metrics);
      }).toList();

      // Sort descending by qualityScore
      scoredItems.sort((a, b) => b.metrics.qualityScore.compareTo(a.metrics.qualityScore));

      final bestItem = scoredItems.first;
      final recommendedKeepId = bestItem.item.id;

      // Default to selecting all other items for deletion
      final defaultDeleteIds = scoredItems
          .where((i) => i.item.id != recommendedKeepId)
          .map((i) => i.item.id)
          .toSet();

      final duplicateItems = scoredItems.map((scored) {
        return DuplicateGroupItem(
          item: scored.item,
          metrics: scored.metrics,
          isRecommendedKeep: scored.item.id == recommendedKeepId,
        );
      }).toList(growable: false);

      resultGroups.add(
        DuplicateMediaGroup(
          id: groupKey,
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
    resultGroups.sort((a, b) => b.potentialSavingsBytes.compareTo(a.potentialSavingsBytes));

    return resultGroups;
  }
}
