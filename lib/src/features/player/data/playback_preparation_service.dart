import 'dart:io';

import 'package:embyplayer/src/features/download/data/download_manager_service.dart';
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
    Duration? startPosition,
    String? mediaSourceId,
  }) async {
    final resumeAt = fromBeginning
        ? Duration.zero
        : (startPosition ?? item.resumePosition);

    if (item.isLocal) {
      final localLibrary = _localLibrary;
      if (localLibrary == null) {
        throw const PlaybackServiceException('本地媒体库服务尚未初始化。');
      }
      final settingsFuture = _readSettings();
      final plan = await localLibrary.createPlaybackPlan(
        item.copyWith(resumePosition: resumeAt),
      );
      return PreparedPlayback(
        item: item.copyWith(resumePosition: resumeAt),
        plan: plan.copyWith(startPosition: resumeAt),
        settings: await settingsFuture,
      );
    }

    // Check if downloaded offline
    final completedTask = DownloadManagerService.instance.getCompletedTask(
      item.id,
      mediaSourceId: mediaSourceId,
    );
    if (completedTask != null) {
      final file = File(completedTask.savePath);
      if (file.existsSync()) {
        final localItem = item.copyWith(
          source: MediaItemSource.local,
          sourcePath: completedTask.savePath,
          resumePosition: resumeAt,
        );
        final settingsFuture = _readSettings();
        final queueFuture = account != null ? _buildQueue(account, item) : null;
        final plan = PlaybackPlan(
          itemId: item.id,
          mediaSourceId: completedTask.mediaSourceId ?? 'local',
          playSessionId: 'offline-${DateTime.now().microsecondsSinceEpoch}',
          streamUri: Uri.file(file.absolute.path, windows: Platform.isWindows),
          method: PlaybackMethod.directPlay,
          duration: item.runTime,
          startPosition: resumeAt,
        );
        return PreparedPlayback(
          item: localItem,
          plan: plan,
          settings: await settingsFuture,
          queue: await queueFuture,
        );
      }
    }

    if (account == null) {
      throw const PlaybackServiceException('请先登录媒体服务器。');
    }

    var targetItem = item;
    var effectiveResumeAt = resumeAt;
    var effectiveStartPosition = startPosition;
    List<MediaItem>? preloadedEpisodes;

    if (targetItem.kind == MediaItemKind.series ||
        targetItem.kind == MediaItemKind.season) {
      final seriesId = targetItem.seriesId ?? targetItem.id;
      final episodes = await _library.getEpisodesForSeries(
        account,
        seriesId: seriesId,
      );
      if (episodes.isEmpty) {
        throw const PlaybackServiceException('该剧集暂无可播放的分集。');
      }
      preloadedEpisodes = episodes;
      final seasonFiltered =
          targetItem.kind == MediaItemKind.season &&
              targetItem.indexNumber != null
          ? episodes
                .where((ep) => ep.parentIndexNumber == targetItem.indexNumber)
                .toList(growable: false)
          : const <MediaItem>[];
      final candidates = seasonFiltered.isNotEmpty ? seasonFiltered : episodes;
      if (fromBeginning) {
        targetItem = candidates.first;
        effectiveResumeAt = Duration.zero;
        effectiveStartPosition = Duration.zero;
      } else {
        targetItem =
            candidates
                .where((ep) => ep.resumePosition > Duration.zero)
                .firstOrNull ??
            candidates.where((ep) => !ep.played).firstOrNull ??
            candidates.first;
        effectiveResumeAt = targetItem.resumePosition;
        effectiveStartPosition = targetItem.resumePosition;
      }
    }

    final queueFuture = preloadedEpisodes != null
        ? Future.value(
            PlaybackQueue.fromEpisodes(
              current: targetItem,
              episodes: preloadedEpisodes,
            ),
          )
        : _buildQueue(account, targetItem);
    final settingsFuture = _readSettings();
    final plan = await _playback.createPlan(
      account,
      targetItem,
      startPosition: fromBeginning ? Duration.zero : effectiveStartPosition,
      mediaSourceId: targetItem.id == item.id ? mediaSourceId : null,
    );
    return PreparedPlayback(
      item: targetItem.copyWith(resumePosition: effectiveResumeAt),
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
