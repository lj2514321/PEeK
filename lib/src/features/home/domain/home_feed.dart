import 'package:embyplayer/src/features/servers/domain/media_item.dart';

class HomeFeedSection {
  const HomeFeedSection({
    this.items = const [],
    this.error,
    this.authenticationExpired = false,
  });

  final List<MediaItem> items;
  final String? error;
  final bool authenticationExpired;

  bool get isEmpty => items.isEmpty;
  bool get hasError => error != null;
}

class HomeFeed {
  const HomeFeed({
    this.dailyRecommendations = const HomeFeedSection(),
    required this.continueWatching,
    required this.latestMovies,
    required this.latestEpisodes,
  });

  final HomeFeedSection dailyRecommendations;
  final HomeFeedSection continueWatching;
  final HomeFeedSection latestMovies;
  final HomeFeedSection latestEpisodes;

  List<HomeFeedSection> get sections => [
    dailyRecommendations,
    continueWatching,
    latestMovies,
    latestEpisodes,
  ];

  MediaItem? get heroItem {
    if (dailyRecommendations.items.isNotEmpty) {
      return dailyRecommendations.items.first;
    }
    if (continueWatching.items.isNotEmpty) {
      return continueWatching.items.first;
    }
    if (latestMovies.items.isNotEmpty) return latestMovies.items.first;
    if (latestEpisodes.items.isNotEmpty) return latestEpisodes.items.first;
    return null;
  }

  List<MediaItem> get heroItems {
    if (dailyRecommendations.items.isNotEmpty) {
      return dailyRecommendations.items;
    }
    final fallback = heroItem;
    return fallback == null ? const [] : [fallback];
  }

  bool get isEmpty => sections.every((section) => section.isEmpty);
  bool get hasAnyError => sections.any((section) => section.hasError);
}
