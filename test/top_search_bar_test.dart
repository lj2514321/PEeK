import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/storage/search_history_store.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/people/data/actor_favorites_store.dart';
import 'package:embyplayer/src/features/people/presentation/actor_favorites_provider.dart';
import 'package:embyplayer/src/features/people/presentation/person_works_page.dart';
import 'package:embyplayer/src/features/search/presentation/top_search_bar.dart';
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

  testWidgets('renders top search bar and opens dropdown panel on tap', (
    tester,
  ) async {
    final historyStore = MemorySearchHistoryStore(['星际穿越', '奥本海默']);
    await tester.pumpWidget(
      _testApp(
        account: account,
        service: _FakeSearchService(),
        historyStore: historyStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('top-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-dropdown-panel')), findsNothing);

    // Tap to focus and open dropdown panel
    await tester.tap(find.byKey(const ValueKey('top-search-field')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-dropdown-panel')), findsOneWidget);
    expect(find.text('最近搜索'), findsOneWidget);
    expect(find.text('星际穿越'), findsOneWidget);
    expect(find.text('奥本海默'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searches for media and renders results in dropdown panel', (
    tester,
  ) async {
    final service = _FakeSearchService();
    await tester.pumpWidget(_testApp(account: account, service: service));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('top-search-field')),
      '示例',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-dropdown-panel')), findsOneWidget);
    expect(find.text('示例电影'), findsOneWidget);
    expect(find.text('示例演员'), findsOneWidget);
    expect(service.searchQueries, contains('示例'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tapping a person in search results opens PersonWorksPage instead of MediaDetailPage',
    (tester) async {
      final service = _FakeSearchService();
      await tester.pumpWidget(_testApp(account: account, service: service));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('top-search-field')),
        '示例',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('示例演员'), findsOneWidget);

      // Tap on person item
      await tester.tap(find.text('示例演员'));
      await tester.pumpAndSettle();

      // Verify PersonWorksPage is opened, and MediaDetailPage is NOT opened
      expect(find.byType(PersonWorksPage), findsOneWidget);
      expect(find.byType(MediaDetailPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tapping a movie in search results opens MediaDetailPage', (
    tester,
  ) async {
    final service = _FakeSearchService();
    await tester.pumpWidget(_testApp(account: account, service: service));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('top-search-field')),
      '示例',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('示例电影'), findsOneWidget);

    // Tap on movie item
    await tester.tap(find.text('示例电影'));
    await tester.pumpAndSettle();

    // Verify MediaDetailPage is opened
    expect(find.byType(MediaDetailPage), findsOneWidget);
    expect(find.byType(PersonWorksPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows guidance when server is not connected', (tester) async {
    await tester.pumpWidget(
      _testApp(account: null, service: _FakeSearchService()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('top-search-field')));
    await tester.pumpAndSettle();

    expect(find.text('请先连接服务器后再进行搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp({
  required AuthenticatedServer? account,
  required MediaLibraryService service,
  SearchHistoryStore? historyStore,
  ActorFavoritesStore? actorStore,
}) {
  return ProviderScope(
    overrides: [
      mediaLibraryProvider.overrideWithValue(service),
      searchHistoryStoreProvider.overrideWithValue(
        historyStore ?? MemorySearchHistoryStore(),
      ),
      actorFavoritesStoreProvider.overrideWithValue(
        actorStore ?? MemoryActorFavoritesStore(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(child: TopSearchBar(account: account)),
      ),
    ),
  );
}

class _FakeSearchService extends MediaLibraryService {
  _FakeSearchService() : super(Dio());

  final searchQueries = <String>[];

  @override
  Future<MediaPage> search(
    AuthenticatedServer account, {
    required String query,
    MediaSearchScope scope = MediaSearchScope.all,
    int startIndex = 0,
    int limit = 40,
    bool forceRefresh = false,
  }) async {
    searchQueries.add(query);
    const items = [
      MediaItem(
        id: 'movie-id',
        name: '示例电影',
        kind: MediaItemKind.movie,
        productionYear: 2026,
      ),
      MediaItem(id: 'person-id', name: '示例演员', kind: MediaItemKind.person),
    ];
    return const MediaPage(
      items: items,
      totalRecordCount: 2,
      nextStartIndex: 2,
    );
  }

  @override
  Future<MediaItem> getItem(
    AuthenticatedServer account,
    String itemId, {
    bool forceRefresh = false,
  }) async {
    return const MediaItem(
      id: 'movie-id',
      name: '示例电影',
      kind: MediaItemKind.movie,
      productionYear: 2026,
    );
  }

  @override
  Future<List<MediaItem>> getSimilar(
    AuthenticatedServer account,
    String itemId, {
    int limit = 12,
    bool forceRefresh = false,
  }) async {
    return const [];
  }

  @override
  Future<MediaPage> getItemsForPerson(
    AuthenticatedServer account, {
    required String personId,
    int startIndex = 0,
    int limit = 40,
    bool forceRefresh = false,
  }) async {
    return const MediaPage(
      items: [
        MediaItem(id: 'work-1', name: '参演代表作', kind: MediaItemKind.movie),
      ],
      totalRecordCount: 1,
      nextStartIndex: 1,
    );
  }
}
