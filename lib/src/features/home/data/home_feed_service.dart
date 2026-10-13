import 'package:embyplayer/src/features/home/domain/home_feed.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

class HomeFeedService {
  const HomeFeedService(this._library);

  final MediaLibraryService _library;
  static const _latestMovieLimitPerLibrary = 12;
  static const _libraryRequestConcurrency = 4;

  Future<HomeFeed> load(
    AuthenticatedServer account, {
    bool forceRefresh = false,
  }) async {
    final latestMoviesFuture = _loadLatestMoviesByLibrary(
      account,
      forceRefresh: forceRefresh,
    );
    final results = await Future.wait<HomeFeedSection>([
      _capture(() => _library.getRecommendations(account)),
      _capture(
        () => _library.getResumeItems(account, forceRefresh: forceRefresh),
      ),
      _capture(
        () => _library.getLatestEpisodes(account, forceRefresh: forceRefresh),
      ),
    ]);
    final latestMovies = await latestMoviesFuture;
    for (final result in results) {
      if (result.authenticationExpired) {
        throw MediaLibraryException(
          result.error ?? '登录凭据已失效，请重新登录服务器。',
          authenticationExpired: true,
          statusCode: 401,
        );
      }
    }
    if (latestMovies.authenticationExpired) {
      throw MediaLibraryException(
        latestMovies.error ?? '登录凭据已失效，请重新登录服务器。',
        authenticationExpired: true,
        statusCode: 401,
      );
    }
    return HomeFeed(
      dailyRecommendations: _withoutResumableDuplicates(results[0], results[1]),
      continueWatching: results[1],
      latestMovies: latestMovies,
      latestEpisodes: results[2],
    );
  }

  Future<HomeFeed> refreshContinueWatching(
    AuthenticatedServer account,
    HomeFeed currentFeed,
  ) async {
    final refreshed = await _capture(
      () => _library.getResumeItems(
        account,
        forceRefresh: true,
        excludeActiveSessions: false,
      ),
    );
    if (refreshed.authenticationExpired) {
      throw MediaLibraryException(
        refreshed.error ?? '登录凭据已失效，请重新登录服务器。',
        authenticationExpired: true,
        statusCode: 401,
      );
    }

    final continueWatching = refreshed.hasError
        ? HomeFeedSection(
            items: currentFeed.continueWatching.items,
            error: refreshed.error,
          )
        : refreshed;
    return HomeFeed(
      dailyRecommendations: currentFeed.dailyRecommendations,
      continueWatching: continueWatching,
      latestMovies: currentFeed.latestMovies,
      latestEpisodes: currentFeed.latestEpisodes,
    );
  }

  Future<HomeFeed> refreshRecommendations(
    AuthenticatedServer account,
    HomeFeed currentFeed,
  ) async {
    final refreshed = await _capture(
      () => _library.getRecommendations(account, forceRefresh: true),
    );
    if (refreshed.authenticationExpired) {
      throw MediaLibraryException(
        refreshed.error ?? '登录凭据已失效，请重新登录服务器。',
        authenticationExpired: true,
        statusCode: 401,
      );
    }
    if (refreshed.hasError) return currentFeed;

    return HomeFeed(
      dailyRecommendations: _withoutResumableDuplicates(
        refreshed,
        currentFeed.continueWatching,
      ),
      continueWatching: currentFeed.continueWatching,
      latestMovies: currentFeed.latestMovies,
      latestEpisodes: currentFeed.latestEpisodes,
    );
  }

  HomeFeedSection _withoutResumableDuplicates(
    HomeFeedSection recommendations,
    HomeFeedSection continueWatching,
  ) {
    if (recommendations.items.isEmpty || continueWatching.items.isEmpty) {
      return recommendations;
    }
    final resumableIds = continueWatching.items.map((item) => item.id).toSet();
    return HomeFeedSection(
      items: recommendations.items
          .where((item) => !resumableIds.contains(item.id))
          .toList(growable: false),
      error: recommendations.error,
      authenticationExpired: recommendations.authenticationExpired,
    );
  }

  Future<HomeFeedSection> _capture(
    Future<List<MediaItem>> Function() request,
  ) async {
    try {
      return HomeFeedSection(items: await request());
    } on MediaLibraryException catch (error) {
      return HomeFeedSection(
        error: error.message,
        authenticationExpired: error.authenticationExpired,
      );
    } on Object {
      return const HomeFeedSection(error: '内容暂时无法读取，请稍后重试。');
    }
  }

  Future<HomeFeedLibrarySections> _loadLatestMoviesByLibrary(
    AuthenticatedServer account, {
    required bool forceRefresh,
  }) async {
    final List<MediaItem> libraries;
    try {
      libraries = await _library.getLibraries(
        account,
        forceRefresh: forceRefresh,
      );
    } on MediaLibraryException catch (error) {
      return HomeFeedLibrarySections(
        error: error.message,
        authenticationExpired: error.authenticationExpired,
      );
    } on Object {
      return const HomeFeedLibrarySections(error: '无法读取电影媒体库。');
    }

    final movieLibraries = libraries
        .where(_canContainMovies)
        .toList(growable: false);
    final groups = <HomeFeedLibrarySection>[];
    for (
      var start = 0;
      start < movieLibraries.length;
      start += _libraryRequestConcurrency
    ) {
      final end = (start + _libraryRequestConcurrency).clamp(
        0,
        movieLibraries.length,
      );
      final batch = movieLibraries.sublist(start, end);
      final sections = await Future.wait(
        batch.map(
          (library) => _capture(
            () => _library.getLatestMovies(
              account,
              parentId: library.id,
              limit: _latestMovieLimitPerLibrary,
              forceRefresh: forceRefresh,
            ),
          ),
        ),
      );
      for (var index = 0; index < batch.length; index++) {
        final section = sections[index];
        if (section.authenticationExpired) {
          return HomeFeedLibrarySections(
            groups: groups,
            error: section.error,
            authenticationExpired: true,
          );
        }
        groups.add(
          HomeFeedLibrarySection(library: batch[index], section: section),
        );
      }
    }
    return HomeFeedLibrarySections(groups: groups);
  }

  bool _canContainMovies(MediaItem library) {
    final type = library.collectionType?.trim().toLowerCase();
    return type == null || type.isEmpty || type == 'movies' || type == 'mixed';
  }
}
