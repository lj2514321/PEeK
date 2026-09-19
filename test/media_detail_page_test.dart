import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final account = AuthenticatedServer(
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
  const item = MediaItem(
    id: 'movie-id',
    name: '示例电影',
    kind: MediaItemKind.movie,
  );

  for (final size in const [Size(375, 812), Size(1280, 800)]) {
    testWidgets('lays out media details at ${size.width.toInt()} pixels', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaLibraryProvider.overrideWithValue(_FakeDetailService()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: MediaDetailPage(account: account, initialItem: item),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('示例电影'), findsWidgets);
      expect(find.text('立即播放'), findsOneWidget);
      expect(find.text('剧情简介'), findsOneWidget);
      expect(find.text('演员阵容'), findsOneWidget);
      expect(find.text('示例演员'), findsOneWidget);
      expect(find.text('相似推荐'), findsOneWidget);
      expect(find.text('推荐电影'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('toggles favorite and watched state from details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeDetailService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaDetailPage(account: account, initialItem: item),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('detail-favorite-button')));
    await tester.pumpAndSettle();
    expect(service.favoriteValue, isTrue);
    expect(find.widgetWithText(OutlinedButton, '已收藏'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('detail-played-button')));
    await tester.pumpAndSettle();
    expect(service.playedValue, isTrue);
    expect(find.widgetWithText(OutlinedButton, '已观看'), findsOneWidget);
  });

  testWidgets('opens the selected actor filmography from the cast card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeDetailService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaDetailPage(account: account, initialItem: item),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final actorCard = find.byKey(const ValueKey('person-card-person-id'));
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -720),
    );
    await tester.pumpAndSettle();
    await tester.tap(actorCard);
    await tester.pumpAndSettle();

    expect(service.requestedPersonIds, ['person-id']);
    expect(find.byKey(const ValueKey('person-work-credit-id')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('displays seasons and episodes for TV series', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeDetailService();
    const seriesItem = MediaItem(
      id: 'series-id',
      name: '示例剧集',
      kind: MediaItemKind.series,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaDetailPage(account: account, initialItem: seriesItem),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('剧集选集'), findsOneWidget);
    expect(find.text('第一集 序章'), findsOneWidget);
    expect(find.text('第 1 季'), findsOneWidget);
    expect(find.text('第 2 季'), findsOneWidget);
  });

  testWidgets('displays collection badge and section when item belongs to a collection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeDetailService()
      ..collections = const [
        MediaItem(
          id: 'boxset-matrix',
          name: '黑客帝国（系列）',
          kind: MediaItemKind.folder,
        ),
      ]
      ..collectionItems = const [
        MediaItem(
          id: 'movie-id',
          name: '示例电影',
          kind: MediaItemKind.movie,
          productionYear: 2026,
        ),
        MediaItem(
          id: 'movie-2',
          name: '黑客帝国 2',
          kind: MediaItemKind.movie,
          productionYear: 2003,
        ),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaDetailPage(account: account, initialItem: item),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check collection badge in hero
    expect(find.text('所属合集 · 黑客帝国（系列）'), findsOneWidget);

    // Check collection section header and item
    expect(find.textContaining('黑客帝国（系列）'), findsWidgets);
    expect(find.text('黑客帝国 2'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
  });
}

class _FakeDetailService extends MediaLibraryService {
  _FakeDetailService() : super(Dio());

  bool? favoriteValue;
  bool? playedValue;
  final requestedPersonIds = <String>[];
  List<MediaItem> collections = const [];
  List<MediaItem> collectionItems = const [];

  @override
  Future<List<MediaItem>> getCollectionsForItem(
    AuthenticatedServer account,
    String itemId, {
    bool forceRefresh = false,
  }) async {
    return collections;
  }

  @override
  Future<List<MediaItem>> getCollectionItems(
    AuthenticatedServer account,
    String collectionId, {
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    return collectionItems;
  }

  @override
  Future<MediaItem> getItem(
    AuthenticatedServer account,
    String itemId, {
    bool forceRefresh = false,
  }) async {
    if (itemId == 'series-id') {
      return const MediaItem(
        id: 'series-id',
        name: '示例剧集',
        kind: MediaItemKind.series,
        overview: '剧集简介。',
      );
    }
    return const MediaItem(
      id: 'movie-id',
      name: '示例电影',
      kind: MediaItemKind.movie,
      overview: '一段用于验证详情页布局的电影简介。',
      productionYear: 2026,
      runTime: Duration(minutes: 108),
      genres: ['剧情', '科幻'],
      communityRating: 8.4,
      officialRating: 'PG-13',
      people: [
        MediaPerson(id: 'person-id', name: '示例演员', type: 'Actor', role: '主角'),
      ],
    );
  }

  @override
  Future<List<MediaItem>> getEpisodesForSeries(
    AuthenticatedServer account, {
    required String seriesId,
    bool forceRefresh = false,
  }) async {
    return const [
      MediaItem(
        id: 'ep-1',
        name: '第一集 序章',
        kind: MediaItemKind.episode,
        indexNumber: 1,
        parentIndexNumber: 1,
        runTime: Duration(minutes: 45),
      ),
      MediaItem(
        id: 'ep-2',
        name: '第二集 启程',
        kind: MediaItemKind.episode,
        indexNumber: 2,
        parentIndexNumber: 1,
        runTime: Duration(minutes: 48),
      ),
      MediaItem(
        id: 'ep-3',
        name: '第二季 第一集',
        kind: MediaItemKind.episode,
        indexNumber: 1,
        parentIndexNumber: 2,
        runTime: Duration(minutes: 50),
      ),
    ];
  }

  @override
  Future<List<MediaItem>> getSimilar(
    AuthenticatedServer account,
    String itemId, {
    int limit = 12,
    bool forceRefresh = false,
  }) async {
    return const [
      MediaItem(
        id: 'similar-id',
        name: '推荐电影',
        kind: MediaItemKind.movie,
        productionYear: 2025,
      ),
    ];
  }

  @override
  Future<MediaPage> getItemsForPerson(
    AuthenticatedServer account, {
    required String personId,
    int startIndex = 0,
    int limit = 40,
    bool forceRefresh = false,
  }) async {
    requestedPersonIds.add(personId);
    return const MediaPage(
      items: [
        MediaItem(
          id: 'credit-id',
          name: '演员作品',
          kind: MediaItemKind.movie,
          productionYear: 2026,
        ),
      ],
      totalRecordCount: 1,
      nextStartIndex: 1,
    );
  }

  @override
  Future<void> setFavorite(
    AuthenticatedServer account,
    String itemId, {
    required bool favorite,
  }) async {
    favoriteValue = favorite;
  }

  @override
  Future<void> setPlayed(
    AuthenticatedServer account,
    String itemId, {
    required bool played,
  }) async {
    playedValue = played;
  }
}
