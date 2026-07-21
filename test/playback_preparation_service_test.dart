import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/player/data/playback_preparation_service.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/data/playback_settings_store.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final account = _account();

  test('prepares a shared playback plan and episode queue', () async {
    final playback = _FakePlaybackService();
    final preparation = PlaybackPreparationService(
      playback,
      _FakeEpisodeLibrary(),
      MemoryPlaybackSettingsStore(
        const PlaybackSettings(
          hardwareDecodingMode: HardwareDecodingMode.software,
        ),
      ),
    );
    const episode = MediaItem(
      id: 'episode-2',
      name: '第二集',
      kind: MediaItemKind.episode,
      seriesId: 'series-id',
      parentIndexNumber: 1,
      indexNumber: 2,
    );

    final prepared = await preparation.prepare(account, episode);

    expect(prepared.plan.itemId, 'episode-2');
    expect(prepared.queue?.items, hasLength(2));
    expect(prepared.queue?.currentIndex, 1);
    expect(playback.requestedStartPosition, isNull);
    expect(
      prepared.settings.hardwareDecodingMode,
      HardwareDecodingMode.software,
    );
  });

  test('can explicitly prepare playback from the beginning', () async {
    final playback = _FakePlaybackService();
    final preparation = PlaybackPreparationService(
      playback,
      _FakeEpisodeLibrary(),
      MemoryPlaybackSettingsStore(),
    );
    const movie = MediaItem(
      id: 'movie-id',
      name: '电影',
      kind: MediaItemKind.movie,
      resumePosition: Duration(minutes: 20),
    );

    final prepared = await preparation.prepare(
      account,
      movie,
      fromBeginning: true,
    );

    expect(prepared.queue, isNull);
    expect(playback.requestedStartPosition, Duration.zero);
  });
}

class _FakePlaybackService extends PlaybackService {
  _FakePlaybackService() : super(Dio());

  Duration? requestedStartPosition;

  @override
  Future<PlaybackPlan> createPlan(
    AuthenticatedServer account,
    MediaItem item, {
    Duration? startPosition,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? mediaSourceId,
    PlaybackBitrate? maxStreamingBitrate,
  }) async {
    requestedStartPosition = startPosition;
    return PlaybackPlan(
      itemId: item.id,
      mediaSourceId: item.id,
      playSessionId: 'session-id',
      streamUri: Uri.parse('https://media.example.test/video.mkv'),
      method: PlaybackMethod.directPlay,
      startPosition: startPosition ?? item.resumePosition,
    );
  }
}

class _FakeEpisodeLibrary extends MediaLibraryService {
  _FakeEpisodeLibrary() : super(Dio());

  @override
  Future<List<MediaItem>> getEpisodesForSeries(
    AuthenticatedServer account, {
    required String seriesId,
    bool forceRefresh = false,
  }) async {
    return const [
      MediaItem(
        id: 'episode-1',
        name: '第一集',
        kind: MediaItemKind.episode,
        seriesId: 'series-id',
        parentIndexNumber: 1,
        indexNumber: 1,
      ),
      MediaItem(
        id: 'episode-2',
        name: '第二集',
        kind: MediaItemKind.episode,
        seriesId: 'series-id',
        parentIndexNumber: 1,
        indexNumber: 2,
      ),
    ];
  }
}

AuthenticatedServer _account() {
  return AuthenticatedServer(
    server: DiscoveredServer(
      kind: ServerKind.jellyfin,
      name: 'Living Room',
      version: '10.11.6',
      serverId: 'server-id',
      apiBaseUri: Uri.parse('http://192.168.1.20:8096'),
    ),
    userId: 'user-id',
    userName: 'Alex',
    deviceId: 'device-id',
    accessToken: 'secret-token',
  );
}
