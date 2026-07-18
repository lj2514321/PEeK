import 'package:embyplayer/src/features/home/domain/home_feed.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

class HomeFeedService {
  const HomeFeedService(this._library);

  final MediaLibraryService _library;

  Future<HomeFeed> load(
    AuthenticatedServer account, {
    bool forceRefresh = false,
  }) async {
    final results = await Future.wait([
      _capture(
        () => _library.getRecommendations(account, forceRefresh: forceRefresh),
      ),
      _capture(
        () => _library.getResumeItems(account, forceRefresh: forceRefresh),
      ),
      _capture(
        () => _library.getLatestMovies(account, forceRefresh: forceRefresh),
      ),
      _capture(
        () => _library.getLatestEpisodes(account, forceRefresh: forceRefresh),
      ),
    ]);
    for (final result in results) {
      if (result.authenticationExpired) {
        throw MediaLibraryException(
          result.error ?? '登录凭据已失效，请重新登录服务器。',
          authenticationExpired: true,
          statusCode: 401,
        );
      }
    }
    return HomeFeed(
      dailyRecommendations: _withoutResumableDuplicates(results[0], results[1]),
      continueWatching: results[1],
      latestMovies: results[2],
      latestEpisodes: results[3],
    );
  }

  Future<HomeFeed> refreshContinueWatching(
    AuthenticatedServer account,
    HomeFeed currentFeed,
  ) async {
    final refreshed = await _capture(
      () => _library.getResumeItems(account, forceRefresh: true),
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
}
