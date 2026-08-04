import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/local_library/data/local_media_library_service.dart';
import 'package:embyplayer/src/features/player/data/playback_settings_store.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_queue.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

class PreparedPlayback {
  const PreparedPlayback({
    required this.item,
    required this.plan,
    required this.settings,
    this.queue,
  });

  final MediaItem item;
  final PlaybackPlan plan;
  final PlaybackSettings settings;
  final PlaybackQueue? queue;
}

class PlaybackPreparationService {
  const PlaybackPreparationService(
    this._playback,
    this._library,
    this._settingsStore, [
    this._localLibrary,
  ]);

  final PlaybackService _playback;
  final MediaLibraryService _library;
  final PlaybackSettingsStore _settingsStore;
  final LocalMediaLibraryService? _localLibrary;

  Future<PreparedPlayback> prepare(
    AuthenticatedServer? account,
    MediaItem item, {
    bool fromBeginning = false,
  }) async {
    if (item.isLocal) {
      final localLibrary = _localLibrary;
      if (localLibrary == null) {
        throw const PlaybackServiceException('本地媒体库服务尚未初始化。');
      }
      final settingsFuture = _readSettings();
      final plan = await localLibrary.createPlaybackPlan(item);
      return PreparedPlayback(
        item: item,
        plan: plan,
        settings: await settingsFuture,
      );
    }
    if (account == null) {
      throw const PlaybackServiceException('请先登录媒体服务器。');
    }
    final queueFuture = _buildQueue(account, item);
    final settingsFuture = _readSettings();
    final plan = await _playback.createPlan(
      account,
      item,
      startPosition: fromBeginning ? Duration.zero : null,
    );
    return PreparedPlayback(
      item: item,
      plan: plan,
      settings: await settingsFuture,
      queue: await queueFuture,
    );
  }

  Future<PlaybackSettings> _readSettings() async {
    try {
      return await _settingsStore.read();
    } on Object {
      return const PlaybackSettings();
    }
  }

  Future<PlaybackQueue?> _buildQueue(
    AuthenticatedServer account,
    MediaItem item,
  ) async {
    final seriesId = item.seriesId;
    if (item.kind != MediaItemKind.episode ||
        seriesId == null ||
        seriesId.isEmpty) {
      return null;
    }
    try {
      final episodes = await _library.getEpisodesForSeries(
        account,
        seriesId: seriesId,
      );
      return PlaybackQueue.fromEpisodes(current: item, episodes: episodes);
    } on MediaLibraryException {
      return null;
    }
  }
}
