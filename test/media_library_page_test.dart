import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/library/presentation/media_library_page.dart';
import 'package:embyplayer/src/features/local_library/data/local_media_library_service.dart';
import 'package:embyplayer/src/features/local_library/data/local_media_library_store.dart';
import 'package:embyplayer/src/features/local_library/domain/local_media_library.dart';
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

  for (final size in const [Size(375, 812), Size(768, 900), Size(1280, 800)]) {
    testWidgets('lays out media library at ${size.width.toInt()} pixels', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaLibraryProvider.overrideWithValue(_FakeLibraryService()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: MediaLibraryPage(account: account, onGoHome: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('晚上好，Alex'), findsOneWidget);
      expect(find.text('电影 1'), findsOneWidget);
      final librarySelector = find.byKey(const ValueKey('library-selector'));
      expect(librarySelector, findsOneWidget);
      await tester.drag(librarySelector, const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(find.text('媒体库 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loads the next page when scrolling near the end', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeLibraryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MediaLibraryPage(account: account, onGoHome: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.requestedStartIndexes, [0]);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -10000),
    );
    await tester.pumpAndSettle();

    expect(service.requestedStartIndexes, contains(60));
    expect(find.text('电影 61'), findsOneWidget);
  });

  testWidgets('browses a local library without a server account', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localMediaLibraryProvider.overrideWithValue(
            _FakeLocalLibraryService(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MediaLibraryPage(
              account: null,
              localLibraries: [
                LocalMediaLibrary(
                  id: 'local-library',
                  name: '本地电影',
                  path: r'C:\Media',
                  addedAt: DateTime(2026, 8, 4),
                ),
              ],
              onGoHome: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你的本地放映架'), findsOneWidget);
    expect(find.text('Local Movie 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-select-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applies sorting, filters, year and grid density', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeLibraryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MediaLibraryPage(account: account, onGoHome: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialGrid = tester.widget<GridView>(find.byType(GridView));
    final initialColumns =
        (initialGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount;
    await tester.tap(find.byTooltip('紧凑视图'));
    await tester.pump();
    final compactGrid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (compactGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      initialColumns + 1,
    );

    await tester.tap(find.byKey(const ValueKey('library-sort-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('评分最高').last);
    await tester.pumpAndSettle();
    expect(service.requestedSorts.last, MediaLibrarySort.ratingDescending);

    await tester.tap(find.byKey(const ValueKey('library-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '电影'));
    await tester.tap(find.widgetWithText(FilterChip, '已收藏'));
    await tester.enterText(
      find.byKey(const ValueKey('library-year-filter')),
      '2025',
    );
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();

    expect(service.requestedKinds.last, MediaLibraryKindFilter.movies);
    expect(service.requestedStatuses.last, MediaLibraryStatusFilter.favorites);
    expect(service.requestedYears.last, 2025);
    expect(find.text('筛选 · 3'), findsOneWidget);
  });

  testWidgets('supports favorite and played bulk actions', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeLibraryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MediaLibraryPage(account: account, onGoHome: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('library-select-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('media-card-artwork-item-0')));
    await tester.pump();
    expect(find.text('已选择 1 项'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bulk-favorite-button')));
    await tester.pumpAndSettle();

    expect(service.favoriteIds, {'item-0'});
    expect(service.favoriteValue, isTrue);
    expect(find.text('已收藏 1 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-select-button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('media-card-artwork-item-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-played-button')));
    await tester.pumpAndSettle();

    expect(service.playedIds, {'item-1'});
    expect(service.playedValue, isTrue);
  });

  testWidgets('opens nested series content and shows a breadcrumb', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeLibraryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MediaLibraryPage(account: account, onGoHome: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final seriesTitle = find.text('示例剧集');
    expect(seriesTitle, findsOneWidget);
    final titleCenter = tester.getCenter(seriesTitle);
    await tester.tapAt(Offset(titleCenter.dx, titleCenter.dy - 100));
    await tester.pumpAndSettle();

    expect(service.requestedParentIds.last, 'series-id');
    expect(find.text('第 1 季'), findsOneWidget);
    expect(find.text('媒体库 1'), findsWidgets);
  });

  testWidgets('supports bulk selection and batch delete', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fakeService = _FakeLibraryService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaLibraryProvider.overrideWithValue(fakeService),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MediaLibraryPage(account: account, onGoHome: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter selection mode via toolbar
    final selectButton = find.byKey(const ValueKey('library-select-button'));
    expect(selectButton, findsOneWidget);
    await tester.tap(selectButton);
    await tester.pump();

    // Select item-0
    await tester.tap(find.byKey(const ValueKey('media-card-artwork-item-0')));
    await tester.pump();

    // Tap bulk delete button
    final bulkDeleteButton = find.byKey(const ValueKey('bulk-delete-button'));
    expect(bulkDeleteButton, findsOneWidget);
    await tester.tap(bulkDeleteButton);
    await tester.pumpAndSettle();

    // Confirm delete dialog
    expect(find.text('确认删除'), findsOneWidget);
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(fakeService.deletedIds, isNotEmpty);
  });
}

void _noop() {}

class _FakeLocalLibraryService extends LocalMediaLibraryService {
  _FakeLocalLibraryService() : super(MemoryLocalMediaLibraryStore());

  @override
  MediaItem libraryItem(LocalMediaLibrary library) {
    return const MediaItem(
      id: 'local-library:local-library',
      name: '本地电影',
      kind: MediaItemKind.folder,
      source: MediaItemSource.local,
      sourcePath: r'C:\Media',
    );
  }

  @override
  Future<MediaPage> getItems(
    MediaItem parent, {
    int startIndex = 0,
    int limit = 60,
    MediaLibrarySort sort = MediaLibrarySort.nameAscending,
    MediaLibraryKindFilter kind = MediaLibraryKindFilter.all,
    MediaLibraryStatusFilter status = MediaLibraryStatusFilter.all,
    MediaResolutionFilter resolution = MediaResolutionFilter.all,
    double? minCommunityRating,
    int? productionYear,
  }) async {
    return const MediaPage(
      items: [
        MediaItem(
          id: 'local-item',
          name: 'Local Movie 2026',
          kind: MediaItemKind.video,
          source: MediaItemSource.local,
          sourcePath: r'C:\Media\Local.Movie.2026.mkv',
        ),
      ],
      totalRecordCount: 1,
      nextStartIndex: 1,
    );
  }
}

class _FakeLibraryService extends MediaLibraryService {
  _FakeLibraryService() : super(Dio());

  final requestedStartIndexes = <int>[];
  final requestedParentIds = <String>[];
  final requestedSorts = <MediaLibrarySort>[];
  final requestedKinds = <MediaLibraryKindFilter>[];
  final requestedStatuses = <MediaLibraryStatusFilter>[];
  final requestedYears = <int?>[];
  Set<String> favoriteIds = {};
  bool? favoriteValue;
  Set<String> playedIds = {};
  bool? playedValue;

  @override
  Future<List<MediaItem>> getLibraries(
    AuthenticatedServer account, {
    bool forceRefresh = false,
  }) async {
    return List.generate(
      8,
      (index) => MediaItem(
        id: 'library-$index',
        name: '媒体库 ${index + 1}',
        kind: MediaItemKind.folder,
      ),
    );
  }

  @override
  Future<MediaPage> getItems(
    AuthenticatedServer account, {
    required String parentId,
    int startIndex = 0,
    int limit = 60,
    MediaLibrarySort sort = MediaLibrarySort.nameAscending,
    MediaLibraryKindFilter kind = MediaLibraryKindFilter.all,
    MediaLibraryStatusFilter status = MediaLibraryStatusFilter.all,
    MediaResolutionFilter resolution = MediaResolutionFilter.all,
    double? minCommunityRating,
    int? productionYear,
    bool forceRefresh = false,
  }) async {
    requestedStartIndexes.add(startIndex);
    requestedParentIds.add(parentId);
    requestedSorts.add(sort);
    requestedKinds.add(kind);
    requestedStatuses.add(status);
    requestedYears.add(productionYear);
    final allItems = parentId == 'series-id'
        ? const [
            MediaItem(
              id: 'season-id',
              name: '第 1 季',
              kind: MediaItemKind.season,
            ),
          ]
        : [
            const MediaItem(
              id: 'series-id',
              name: '示例剧集',
              kind: MediaItemKind.series,
            ),
            ...List.generate(
              125,
              (index) => MediaItem(
                id: 'item-$index',
                name: '电影 ${index + 1}',
                kind: MediaItemKind.movie,
                productionYear: 2026,
                runTime: const Duration(minutes: 108),
              ),
            ),
          ];
    final end = (startIndex + limit).clamp(0, allItems.length);
    return MediaPage(
      items: startIndex >= allItems.length
          ? const []
          : allItems.sublist(startIndex, end),
      totalRecordCount: allItems.length,
      nextStartIndex: end,
    );
  }

  @override
  Future<void> setFavoriteForItems(
    AuthenticatedServer account,
    Iterable<String> itemIds, {
    required bool favorite,
  }) async {
    favoriteIds = itemIds.toSet();
    favoriteValue = favorite;
  }

  @override
  Future<void> setPlayedForItems(
    AuthenticatedServer account,
    Iterable<String> itemIds, {
    required bool played,
  }) async {
    playedIds = itemIds.toSet();
    playedValue = played;
  }

  final List<String> deletedIds = [];

  @override
  Future<void> deleteItem(
    AuthenticatedServer account,
    String itemId,
  ) async {
    deletedIds.add(itemId);
  }
}
