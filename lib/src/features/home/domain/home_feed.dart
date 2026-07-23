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

class HomeFeedLibrarySection {
  const HomeFeedLibrarySection({required this.library, required this.section});

  final MediaItem library;
  final HomeFeedSection section;
}

class HomeFeedLibrarySections {
  const HomeFeedLibrarySections({
    this.groups = const [],
    this.error,
    this.authenticationExpired = false,
  });

  final List<HomeFeedLibrarySection> groups;
  final String? error;
  final bool authenticationExpired;

  bool get isEmpty => groups.every((group) => group.section.isEmpty);
  bool get hasError =>
      error != null || groups.any((group) => group.section.hasError);
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
  final HomeFeedLibrarySections latestMovies;
  final HomeFeedSection latestEpisodes;

  List<HomeFeedSection> get sections => [
    dailyRecommendations,
    continueWatching,
    for (final group in latestMovies.groups) group.section,
    latestEpisodes,
  ];

  MediaItem? get heroItem {
    if (dailyRecommendations.items.isNotEmpty) {
      return dailyRecommendations.items.first;
    }
    if (continueWatching.items.isNotEmpty) {
      return continueWatching.items.first;
    }
    for (final group in latestMovies.groups) {
      if (group.section.items.isNotEmpty) return group.section.items.first;
    }
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
  bool get hasAnyError =>
      latestMovies.hasError || sections.any((section) => section.hasError);
}
