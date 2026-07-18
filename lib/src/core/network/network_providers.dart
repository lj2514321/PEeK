import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/network/session_expiry_coordinator.dart';
import 'package:embyplayer/src/core/storage/media_cache_store.dart';
import 'package:embyplayer/src/core/storage/search_history_store.dart';
import 'package:embyplayer/src/core/storage/secure_token_store.dart';
import 'package:embyplayer/src/features/home/data/home_feed_service.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/data/playback_preparation_service.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/data/server_authentication_service.dart';
import 'package:embyplayer/src/features/servers/data/server_discovery_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sessionExpiryProvider = Provider<SessionExpiryCoordinator>((ref) {
  final coordinator = SessionExpiryCoordinator();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
      headers: const {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(
    SessionExpiryInterceptor(ref.watch(sessionExpiryProvider)),
  );
  return dio;
});

final serverDiscoveryProvider = Provider<ServerDiscoveryService>((ref) {
  return ServerDiscoveryService(ref.watch(dioProvider));
});

final mediaCacheStoreProvider = Provider<MediaCacheStore>((ref) {
  return JsonFileMediaCacheStore();
});

final searchHistoryStoreProvider = Provider<SearchHistoryStore>((ref) {
  return JsonSearchHistoryStore();
});

final mediaLibraryProvider = Provider<MediaLibraryService>((ref) {
  return MediaLibraryService(
    ref.watch(dioProvider),
    ref.watch(mediaCacheStoreProvider),
  );
});

final homeFeedProvider = Provider<HomeFeedService>((ref) {
  return HomeFeedService(ref.watch(mediaLibraryProvider));
});

final playbackServiceProvider = Provider<PlaybackService>((ref) {
  return PlaybackService(ref.watch(dioProvider));
});

final playbackPreparationProvider = Provider<PlaybackPreparationService>((ref) {
  return PlaybackPreparationService(
    ref.watch(playbackServiceProvider),
    ref.watch(mediaLibraryProvider),
  );
});

final secureTokenStoreProvider = Provider<SecureTokenStore>((ref) {
  return SecureTokenStore();
});

final serverAuthenticationProvider = Provider<ServerAuthenticationService>((
  ref,
) {
  return ServerAuthenticationService(
    ref.watch(dioProvider),
    ref.watch(secureTokenStoreProvider),
  );
});
