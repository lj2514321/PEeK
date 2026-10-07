import 'package:embyplayer/src/features/servers/domain/media_item.dart';

class PlaybackQueue {
  const PlaybackQueue({required this.items, required this.currentIndex})
    : assert(items.length > 0),
      assert(currentIndex >= 0 && currentIndex < items.length);

  factory PlaybackQueue.fromEpisodes({
    required MediaItem current,
    required Iterable<MediaItem> episodes,
  }) {
    final currentIsSpecial = current.parentIndexNumber == 0;
    final unique = <String, MediaItem>{
      for (final episode in episodes)
        if (episode.kind == MediaItemKind.episode &&
            (currentIsSpecial
                ? episode.parentIndexNumber == 0
                : episode.parentIndexNumber != 0))
          episode.id: episode,
      current.id: current,
    };
    final items = unique.values.toList()..sort(_compareEpisodes);
    final currentIndex = items.indexWhere((item) => item.id == current.id);
    return PlaybackQueue(items: items, currentIndex: currentIndex);
  }

  final List<MediaItem> items;
  final int currentIndex;

  MediaItem get current => items[currentIndex];

  MediaItem? get previous => currentIndex > 0 ? items[currentIndex - 1] : null;

  MediaItem? get next =>
      currentIndex + 1 < items.length ? items[currentIndex + 1] : null;

  bool get hasPrevious => previous != null;

  bool get hasNext => next != null;

  PlaybackQueue select(int index) {
    if (index < 0 || index >= items.length) return this;
    return PlaybackQueue(items: items, currentIndex: index);
  }

  int indexOf(String itemId) {
    return items.indexWhere((item) => item.id == itemId);
  }

  Map<String, dynamic> toJson() => {
    'items': items.map((item) => item.toJson()).toList(),
    'currentIndex': currentIndex,
  };

  factory PlaybackQueue.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List? ?? const [])
        .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final idx = json['currentIndex'] as int? ?? 0;
    if (rawItems.isEmpty) {
      throw ArgumentError('PlaybackQueue.fromJson: items must not be empty');
    }
    final safeIdx = (idx >= 0 && idx < rawItems.length) ? idx : 0;
    return PlaybackQueue(items: rawItems, currentIndex: safeIdx);
  }
}

int _compareEpisodes(MediaItem left, MediaItem right) {
  final seasonComparison = (left.parentIndexNumber ?? 9999).compareTo(
    right.parentIndexNumber ?? 9999,
  );
  if (seasonComparison != 0) return seasonComparison;
  final episodeComparison = (left.indexNumber ?? 9999).compareTo(
    right.indexNumber ?? 9999,
  );
  if (episodeComparison != 0) return episodeComparison;
  return left.name.toLowerCase().compareTo(right.name.toLowerCase());
}
