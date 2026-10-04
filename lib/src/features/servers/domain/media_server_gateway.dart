import 'package:embyplayer/src/core/domain/playback_plan.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

abstract interface class MediaServerGateway {
  ServerProfile get profile;

  Future<List<MediaItem>> getLibraries();

  Future<List<MediaItem>> getItems({String? parentId, String? query});

  Future<MediaItem> getItem(String itemId);

  Future<PlaybackPlan> createPlaybackPlan(String itemId);

  Future<void> reportPlaybackStarted(PlaybackSessionSnapshot snapshot);

  Future<void> reportPlaybackProgress(PlaybackSessionSnapshot snapshot);

  Future<void> reportPlaybackStopped(PlaybackSessionSnapshot snapshot);
}
