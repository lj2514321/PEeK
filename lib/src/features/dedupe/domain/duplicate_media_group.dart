import 'package:embyplayer/src/features/servers/domain/media_item.dart';

enum DuplicateMatchReason {
  providerId,
  titleAndYear,
  episode,
}

extension DuplicateMatchReasonLabel on DuplicateMatchReason {
  String get label => switch (this) {
    DuplicateMatchReason.providerId => 'TMDb / IMDb 元数据匹配',
    DuplicateMatchReason.titleAndYear => '规范化标题与年份一致',
    DuplicateMatchReason.episode => '同一剧集季集号冲突',
  };

  String get shortTag => switch (this) {
    DuplicateMatchReason.providerId => '精准元数据',
    DuplicateMatchReason.titleAndYear => '标题年份',
    DuplicateMatchReason.episode => '剧集重集',
  };
}

class MediaQualityMetrics {
  const MediaQualityMetrics({
    required this.resolutionLabel,
    required this.is4K,
    required this.isHDR,
    required this.videoCodec,
    required this.audioFormat,
    this.fileSize,
    required this.qualityScore,
    this.advantageTags = const [],
  });

  final String resolutionLabel;
  final bool is4K;
  final bool isHDR;
  final String videoCodec;
  final String audioFormat;
  final int? fileSize;
  final int qualityScore;
  final List<String> advantageTags;

  String get formattedFileSize {
    final size = fileSize;
    if (size == null || size <= 0) return '未知体积';
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(size / 1024).toStringAsFixed(0)} KB';
  }
}

class DuplicateGroupItem {
  const DuplicateGroupItem({
    required this.item,
    required this.metrics,
    required this.isRecommendedKeep,
  });

  final MediaItem item;
  final MediaQualityMetrics metrics;
  final bool isRecommendedKeep;
}

class DuplicateMediaGroup {
  const DuplicateMediaGroup({
    required this.id,
    required this.title,
    this.productionYear,
    required this.matchReason,
    required this.matchDetail,
    required this.items,
    required this.recommendedKeepId,
    this.selectedDeleteIds = const {},
  });

  final String id;
  final String title;
  final int? productionYear;
  final DuplicateMatchReason matchReason;
  final String matchDetail;
  final List<DuplicateGroupItem> items;
  final String recommendedKeepId;
  final Set<String> selectedDeleteIds;

  int get potentialSavingsBytes {
    var sum = 0;
    for (final groupItem in items) {
      if (selectedDeleteIds.contains(groupItem.item.id)) {
        sum += groupItem.metrics.fileSize ?? 0;
      }
    }
    return sum;
  }

  DuplicateMediaGroup copyWith({
    Set<String>? selectedDeleteIds,
  }) {
    return DuplicateMediaGroup(
      id: id,
      title: title,
      productionYear: productionYear,
      matchReason: matchReason,
      matchDetail: matchDetail,
      items: items,
      recommendedKeepId: recommendedKeepId,
      selectedDeleteIds: selectedDeleteIds ?? this.selectedDeleteIds,
    );
  }
}
