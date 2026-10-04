import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/network/session_expiry_coordinator.dart';
import 'package:embyplayer/src/core/storage/media_cache_store.dart';
import 'package:embyplayer/src/core/storage/search_history_store.dart';
import 'package:embyplayer/src/core/storage/secure_token_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Export application-level service providers for backward compatibility
export 'package:embyplayer/src/app/app_providers.dart';

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

final mediaCacheStoreProvider = Provider<MediaCacheStore>((ref) {
  return JsonFileMediaCacheStore();
});

final searchHistoryStoreProvider = Provider<SearchHistoryStore>((ref) {
  return JsonSearchHistoryStore();
});

final secureTokenStoreProvider = Provider<SecureTokenStore>((ref) {
  return SecureTokenStore();
});
