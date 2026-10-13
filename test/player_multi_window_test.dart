import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:embyplayer/src/core/domain/media_item.dart';
import 'package:embyplayer/src/core/domain/playback_plan.dart';
import 'package:embyplayer/src/core/domain/playback_settings.dart';
import 'package:embyplayer/src/core/domain/server.dart';
import 'package:embyplayer/src/features/player/domain/playback_queue.dart';
import 'package:embyplayer/src/features/player/domain/player_window_payload.dart';
import 'package:embyplayer/src/features/player/presentation/global_playback_coordinator.dart';

void main() {
  group('PlayerWindowPayload serialization', () {
    test('serializes and deserializes correctly with all fields', () {
      final account = AuthenticatedServer(
        server: DiscoveredServer(
          name: 'Home Emby',
          serverId: 'srv-001',
          version: '4.8.0',
          kind: ServerKind.emby,
          apiBaseUri: Uri.parse('http://192.168.1.100:8096'),
        ),
        userId: 'user-123',
        userName: 'Admin',
        deviceId: 'device-abc',
        accessToken: 'token-xyz',
      );

      final item = MediaItem(
        id: 'item-001',
        name: 'Inception',
        overview: 'A thief who steals corporate secrets...',
        kind: MediaItemKind.movie,
        productionYear: 2010,
        communityRating: 8.8,
        genres: ['Action', 'Sci-Fi'],
        imageUri: Uri.parse(
          'http://192.168.1.100:8096/Items/item-001/Images/Primary',
        ),
      );

      final plan = PlaybackPlan(
        itemId: 'item-001',
        mediaSourceId: 'src-001',
        playSessionId: 'session-001',
        streamUri: Uri.parse(
          'http://192.168.1.100:8096/Videos/item-001/stream.mp4',
        ),
        method: PlaybackMethod.directPlay,
        duration: const Duration(minutes: 148),
        startPosition: const Duration(minutes: 12),
        audioStreamIndex: 1,
        subtitleStreamIndex: 2,
      );

      final queue = PlaybackQueue(items: [item], currentIndex: 0);

      final payload = PlayerWindowPayload(
        account: account,
        item: item,
        plan: plan,
        queue: queue,
        hardwareDecodingMode: HardwareDecodingMode.automatic,
        maxStreamingBitrate: PlaybackBitrate.mbps20,
        subtitlePreferences: const SubtitlePreferences(delayMilliseconds: 200),
        skipIntroPreferences: const SkipIntroPreferences(autoSkip: true),
        danmakuPreferences: const DanmakuPreferences(enabled: true),
      );

      final jsonMap = payload.toJson();
      final jsonStr = jsonEncode(jsonMap);
      final decodedMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restoredPayload = PlayerWindowPayload.fromJson(decodedMap);

      expect(restoredPayload.item.id, equals('item-001'));
      expect(restoredPayload.item.name, equals('Inception'));
      expect(restoredPayload.item.kind, equals(MediaItemKind.movie));
      expect(restoredPayload.account?.userId, equals('user-123'));
      expect(restoredPayload.account?.deviceId, equals('device-abc'));
      expect(restoredPayload.account?.accessToken, equals('token-xyz'));
      expect(restoredPayload.plan.itemId, equals('item-001'));
      expect(
        restoredPayload.plan.startPosition,
        equals(const Duration(minutes: 12)),
      );
      expect(restoredPayload.plan.method, equals(PlaybackMethod.directPlay));
      expect(restoredPayload.queue?.items.length, equals(1));
      expect(
        restoredPayload.hardwareDecodingMode,
        equals(HardwareDecodingMode.automatic),
      );
      expect(
        restoredPayload.maxStreamingBitrate,
        equals(PlaybackBitrate.mbps20),
      );
      expect(restoredPayload.skipIntroPreferences.autoSkip, isTrue);
      expect(restoredPayload.danmakuPreferences.enabled, isTrue);
    });

    test(
      'serializes and deserializes with optional null fields (local playback)',
      () {
        final item = MediaItem(
          id: 'local-001',
          name: 'Local Video',
          kind: MediaItemKind.video,
          source: MediaItemSource.local,
        );

        final plan = PlaybackPlan(
          itemId: 'local-001',
          mediaSourceId: 'local',
          playSessionId: 'local-session',
          streamUri: Uri.file('C:/Videos/test.mp4'),
          method: PlaybackMethod.directPlay,
        );

        final payload = PlayerWindowPayload(
          account: null,
          item: item,
          plan: plan,
        );

        final jsonMap = payload.toJson();
        final jsonStr = jsonEncode(jsonMap);
        final decodedMap = jsonDecode(jsonStr) as Map<String, dynamic>;
        final restored = PlayerWindowPayload.fromJson(decodedMap);

        expect(restored.account, isNull);
        expect(restored.queue, isNull);
        expect(restored.item.id, equals('local-001'));
        expect(restored.item.isLocal, isTrue);
        expect(restored.plan.streamUri.path, contains('test.mp4'));
      },
    );
  });

  group('GlobalPlaybackCoordinator Window Mode', () {
    test('registerWindowPlayback sets mode to window and notifies state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final coordinator = container.read(
        globalPlaybackCoordinatorProvider.notifier,
      );

      final item = MediaItem(
        id: 'w-1',
        name: 'Movie 1',
        kind: MediaItemKind.movie,
      );
      final plan = PlaybackPlan(
        itemId: 'w-1',
        mediaSourceId: 'src-1',
        playSessionId: 'sess-1',
        streamUri: Uri.parse('http://test/stream.mp4'),
        method: PlaybackMethod.directPlay,
        duration: const Duration(minutes: 100),
        startPosition: const Duration(minutes: 5),
      );

      coordinator.registerWindowPlayback(account: null, item: item, plan: plan);

      final state = container.read(globalPlaybackCoordinatorProvider);
      expect(state.mode, equals(PlaybackPresentationMode.window));
      expect(state.item?.id, equals('w-1'));
      expect(state.position, equals(const Duration(minutes: 5)));
      expect(state.duration, equals(const Duration(minutes: 100)));
      expect(state.playing, isTrue);
    });

    test('reportOptimisticProgress updates position and recent positions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final coordinator = container.read(
        globalPlaybackCoordinatorProvider.notifier,
      );
      final item = MediaItem(
        id: 'w-2',
        name: 'Movie 2',
        kind: MediaItemKind.movie,
      );
      final plan = PlaybackPlan(
        itemId: 'w-2',
        mediaSourceId: 'src-2',
        playSessionId: 'sess-2',
        streamUri: Uri.parse('http://test/stream.mp4'),
        method: PlaybackMethod.directPlay,
      );

      coordinator.registerWindowPlayback(account: null, item: item, plan: plan);

      coordinator.reportOptimisticProgress(
        'w-2',
        const Duration(minutes: 30),
        duration: const Duration(minutes: 120),
        playing: true,
      );

      final state = container.read(globalPlaybackCoordinatorProvider);
      expect(state.position, equals(const Duration(minutes: 30)));
      expect(state.duration, equals(const Duration(minutes: 120)));
      expect(
        coordinator.getEffectivePosition('w-2'),
        equals(const Duration(minutes: 30)),
      );
    });

    test('clearActivePlayback resets mode to hidden', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final coordinator = container.read(
        globalPlaybackCoordinatorProvider.notifier,
      );
      final item = MediaItem(
        id: 'w-3',
        name: 'Movie 3',
        kind: MediaItemKind.movie,
      );
      final plan = PlaybackPlan(
        itemId: 'w-3',
        mediaSourceId: 'src-3',
        playSessionId: 'sess-3',
        streamUri: Uri.parse('http://test/stream.mp4'),
        method: PlaybackMethod.directPlay,
      );

      coordinator.registerWindowPlayback(account: null, item: item, plan: plan);
      expect(
        container.read(globalPlaybackCoordinatorProvider).mode,
        equals(PlaybackPresentationMode.window),
      );

      coordinator.clearActivePlayback();
      expect(
        container.read(globalPlaybackCoordinatorProvider).mode,
        equals(PlaybackPresentationMode.hidden),
      );
    });

    test('updateActiveItem updates the current active media item', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final coordinator = container.read(
        globalPlaybackCoordinatorProvider.notifier,
      );
      final item1 = MediaItem(
        id: 'ep-1',
        name: 'Episode 1',
        kind: MediaItemKind.episode,
      );
      final item2 = MediaItem(
        id: 'ep-2',
        name: 'Episode 2',
        kind: MediaItemKind.episode,
      );
      final plan = PlaybackPlan(
        itemId: 'ep-1',
        mediaSourceId: 'src-1',
        playSessionId: 'sess-1',
        streamUri: Uri.parse('http://test/stream.mp4'),
        method: PlaybackMethod.directPlay,
      );

      coordinator.registerWindowPlayback(
        account: null,
        item: item1,
        plan: plan,
      );
      expect(
        container.read(globalPlaybackCoordinatorProvider).item?.name,
        equals('Episode 1'),
      );

      coordinator.updateActiveItem(item2);
      expect(
        container.read(globalPlaybackCoordinatorProvider).item?.name,
        equals('Episode 2'),
      );

      final plan2 = PlaybackPlan(
        itemId: 'ep-2',
        mediaSourceId: 'src-2',
        playSessionId: 'sess-2',
        streamUri: Uri.parse('http://test/stream2.mp4'),
        method: PlaybackMethod.directPlay,
      );
      coordinator.updateActiveItem(item2, plan: plan2);
      expect(
        container.read(globalPlaybackCoordinatorProvider).plan?.itemId,
        equals('ep-2'),
      );
    });

    test('closeMiniSilently sets mode to hidden without errors', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final coordinator = container.read(
        globalPlaybackCoordinatorProvider.notifier,
      );
      coordinator.closeMiniSilently();
      expect(
        container.read(globalPlaybackCoordinatorProvider).mode,
        equals(PlaybackPresentationMode.hidden),
      );
    });
  });

  group('PlayerWindowProtocol constants', () {
    test('contains handoverToMiniPlayer and reportMediaChanged methods', () {
      expect(
        PlayerWindowProtocol.methodHandoverToMiniPlayer,
        equals('handoverToMiniPlayer'),
      );
      expect(
        PlayerWindowProtocol.methodReportMediaChanged,
        equals('reportMediaChanged'),
      );
    });
  });
}
