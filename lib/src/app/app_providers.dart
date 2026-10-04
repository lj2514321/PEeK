import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/home/data/home_feed_service.dart';
import 'package:embyplayer/src/features/local_library/data/local_media_library_service.dart';
import 'package:embyplayer/src/features/local_library/data/local_media_library_store.dart';
import 'package:embyplayer/src/features/player/data/playback_diagnostic_log.dart';
import 'package:embyplayer/src/features/player/data/playback_preparation_service.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/data/playback_settings_store.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/data/server_authentication_service.dart';
import 'package:embyplayer/src/features/servers/data/server_discovery_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Application-level service composition root (Dependency Injection wiring)

final serverDiscoveryProvider = Provider<ServerDiscoveryService>((ref) {
  return ServerDiscoveryService(ref.watch(dioProvider));
});

final localMediaLibraryStoreProvider = Provider<LocalMediaLibraryStore>((ref) {
  return JsonLocalMediaLibraryStore();
});

final localMediaLibraryProvider = Provider<LocalMediaLibraryService>((ref) {
  return LocalMediaLibraryService(ref.watch(localMediaLibraryStoreProvider));
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

final playbackSettingsStoreProvider = Provider<PlaybackSettingsStore>((ref) {
  return JsonPlaybackSettingsStore();
});

final playbackDiagnosticLogProvider = Provider<PlaybackDiagnosticLog>((ref) {
  return PlaybackDiagnosticLog();
});

final playbackServiceProvider = Provider<PlaybackService>((ref) {
  return PlaybackService(
    ref.watch(dioProvider),
    ref.watch(playbackSettingsStoreProvider),
  );
});

final playbackPreparationProvider = Provider<PlaybackPreparationService>((ref) {
  return PlaybackPreparationService(
    ref.watch(playbackServiceProvider),
    ref.watch(mediaLibraryProvider),
    ref.watch(playbackSettingsStoreProvider),
    ref.watch(localMediaLibraryProvider),
  );
});

final serverAuthenticationProvider = Provider<ServerAuthenticationService>((
  ref,
) {
  return ServerAuthenticationService(
    ref.watch(dioProvider),
    ref.watch(secureTokenStoreProvider),
  );
});
