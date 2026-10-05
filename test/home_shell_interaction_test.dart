import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/app.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/storage/search_history_store.dart';
import 'package:embyplayer/src/core/storage/secure_token_store.dart';
import 'package:embyplayer/src/features/player/data/playback_settings_store.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/data/server_authentication_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collapses the desktop sidebar and opens favorites', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = _account();
    final library = _ShellLibraryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverAuthenticationProvider.overrideWithValue(
            _ShellAuthenticationService(account),
          ),
          mediaLibraryProvider.overrideWithValue(library),
          searchHistoryStoreProvider.overrideWithValue(
            MemorySearchHistoryStore(),
          ),
          playbackSettingsStoreProvider.overrideWithValue(
            MemoryPlaybackSettingsStore(),
          ),
        ],
        child: const EmbyPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRIVATE CINEMA'), findsOneWidget);
    final topBar = tester.element(
      find.byKey(const ValueKey('top-command-bar')),
    );
    expect(find.byKey(const ValueKey('top-destination-title')), findsOneWidget);
    expect(find.text('CURRENT VIEW'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('app-sidebar'))).width,
      224,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('main-content-pane'))).dx,
      224,
    );
    await tester.tap(find.byKey(const ValueKey('sidebar-toggle')));
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('app-sidebar'))).width,
      224,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('main-content-pane'))).dx,
      224,
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester.getSize(find.byKey(const ValueKey('app-sidebar'))).width,
      inExclusiveRange(80, 224),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('main-content-pane'))).dx,
      inExclusiveRange(80, 224),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('app-sidebar'))).width, 80);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('main-content-pane'))).dx,
      80,
    );
    expect(find.text('PRIVATE CINEMA'), findsNothing);

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();

    expect(
      tester.element(find.byKey(const ValueKey('top-command-bar'))),
      same(topBar),
    );
    expect(find.text('收藏').first, findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('收藏影片'), findsOneWidget);
    expect(library.favoriteRequests, 1);

    await tester.tap(find.byKey(const ValueKey('sidebar-toggle')));
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('app-sidebar'))).width, 80);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('main-content-pane'))).dx,
      80,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.getSize(find.byKey(const ValueKey('app-sidebar'))).width,
      inExclusiveRange(80, 224),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('main-content-pane'))).dx,
      inExclusiveRange(80, 224),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('app-sidebar'))).width,
      224,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('main-content-pane'))).dx,
      224,
    );
    expect(find.text('PRIVATE CINEMA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens search dropdown and searches from top search bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = _account();
    final library = _ShellLibraryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverAuthenticationProvider.overrideWithValue(
            _ShellAuthenticationService(account),
          ),
          mediaLibraryProvider.overrideWithValue(library),
          searchHistoryStoreProvider.overrideWithValue(
            MemorySearchHistoryStore(),
          ),
          playbackSettingsStoreProvider.overrideWithValue(
            MemoryPlaybackSettingsStore(),
          ),
        ],
        child: const EmbyPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(library.libraryRequests, 1);

    final searchField = find.byKey(const ValueKey('top-search-field'));
    expect(searchField, findsOneWidget);

    await tester.tap(searchField);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-dropdown-panel')), findsOneWidget);

    await tester.enterText(searchField, '保留现场');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('保留现场的结果'), findsOneWidget);
    expect(library.searchRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the actors destination and keeps its state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = _account();
    final library = _ShellLibraryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverAuthenticationProvider.overrideWithValue(
            _ShellAuthenticationService(account),
          ),
          mediaLibraryProvider.overrideWithValue(library),
          searchHistoryStoreProvider.overrideWithValue(
            MemorySearchHistoryStore(),
          ),
          playbackSettingsStoreProvider.overrideWithValue(
            MemoryPlaybackSettingsStore(),
          ),
        ],
        child: const EmbyPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('演员'));
    await tester.pumpAndSettle();

    expect(find.text('演员列表'), findsOneWidget);
    expect(find.text('演员甲'), findsOneWidget);
    expect(library.actorRequests, 1);

    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('演员'));
    await tester.pumpAndSettle();

    expect(find.text('演员甲'), findsOneWidget);
    expect(library.actorRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches to actors with Ctrl+5', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = _account();
    final library = _ShellLibraryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverAuthenticationProvider.overrideWithValue(
            _ShellAuthenticationService(account),
          ),
          mediaLibraryProvider.overrideWithValue(library),
          searchHistoryStoreProvider.overrideWithValue(
            MemorySearchHistoryStore(),
          ),
          playbackSettingsStoreProvider.overrideWithValue(
            MemoryPlaybackSettingsStore(),
          ),
        ],
        child: const EmbyPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('演员列表'), findsOneWidget);
    expect(library.actorRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders six destinations in the compact bottom navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = _account();
    final library = _ShellLibraryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverAuthenticationProvider.overrideWithValue(
            _ShellAuthenticationService(account),
          ),
          mediaLibraryProvider.overrideWithValue(library),
          searchHistoryStoreProvider.overrideWithValue(
            MemorySearchHistoryStore(),
          ),
          playbackSettingsStoreProvider.overrideWithValue(
            MemoryPlaybackSettingsStore(),
          ),
        ],
        child: const EmbyPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('演员'));
    await tester.pumpAndSettle();

    expect(find.text('演员列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renders account status without invalid downward arrow and navigates to server settings',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = _account();
      final library = _ShellLibraryService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverAuthenticationProvider.overrideWithValue(
              _ShellAuthenticationService(account),
            ),
            mediaLibraryProvider.overrideWithValue(library),
            searchHistoryStoreProvider.overrideWithValue(
              MemorySearchHistoryStore(),
            ),
            playbackSettingsStoreProvider.overrideWithValue(
              MemoryPlaybackSettingsStore(),
            ),
          ],
          child: const EmbyPlayerApp(),
        ),
      );
      await tester.pumpAndSettle();

      final accountStatusFinder = find.byKey(
        const ValueKey('top-account-status'),
      );
      expect(accountStatusFinder, findsOneWidget);
      expect(
        find.descendant(of: accountStatusFinder, matching: find.text('Alex')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: accountStatusFinder,
          matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
        ),
        findsNothing,
      );

      await tester.tap(accountStatusFinder);
      await tester.pumpAndSettle();

      expect(find.text('服务器'), findsWidgets);
    },
  );
}

class _ShellAuthenticationService extends ServerAuthenticationService {
  _ShellAuthenticationService(this.account) : super(Dio(), SecureTokenStore());

  final AuthenticatedServer account;

  @override
  Future<ServerAccountState> restoreSessionState() async {
    return ServerAccountState(
      accounts: [
        ServerAccountEntry(
          profile: ServerProfile.fromSession(account),
          session: account,
        ),
      ],
      activeSession: account,
    );
  }
}

class _ShellLibraryService extends MediaLibraryService {
  _ShellLibraryService() : super(Dio());

  int libraryRequests = 0;
  int searchRequests = 0;
  int favoriteRequests = 0;
  int actorRequests = 0;

  @override
  Future<List<MediaItem>> getLibraries(
    AuthenticatedServer account, {
    bool forceRefresh = false,
  }) async {
    libraryRequests += 1;
    return const [
      MediaItem(
        id: 'library',
        name: '电影',
        kind: MediaItemKind.folder,
        collectionType: 'movies',
      ),
    ];
  }

  @override
  Future<MediaPage> getItems(
    AuthenticatedServer account, {
    String? parentId,
    String? collectionType,
    int startIndex = 0,
    int limit = 60,
    MediaLibrarySort sort = MediaLibrarySort.nameAscending,
    MediaLibraryKindFilter kind = MediaLibraryKindFilter.all,
    MediaLibraryStatusFilter status = MediaLibraryStatusFilter.all,
    MediaResolutionFilter resolution = MediaResolutionFilter.all,
    double? minCommunityRating,
    int? productionYear,
    String? tag,
    List<String>? tags,
    bool collapseBoxSets = false,
    bool forceRefresh = false,
  }) async {
    return const MediaPage(items: [], totalRecordCount: 0, nextStartIndex: 0);
  }

  @override
  Future<MediaPage> getFavoriteItems(
    AuthenticatedServer account, {
    int startIndex = 0,
    int limit = 60,
    bool forceRefresh = false,
  }) async {
    favoriteRequests += 1;
    return const MediaPage(
      items: [
        MediaItem(
          id: 'favorite',
          name: '收藏影片',
          kind: MediaItemKind.movie,
          favorite: true,
        ),
      ],
      totalRecordCount: 1,
      nextStartIndex: 1,
    );
  }

  @override
  Future<MediaPage> getActors(
    AuthenticatedServer account, {
    String? parentId,
    int startIndex = 0,
    int limit = 60,
    bool forceRefresh = false,
  }) async {
    actorRequests += 1;
    return const MediaPage(
      items: [
        MediaItem(id: 'actor-a', name: '演员甲', kind: MediaItemKind.person),
        MediaItem(id: 'actor-b', name: '演员乙', kind: MediaItemKind.person),
      ],
      totalRecordCount: 2,
      nextStartIndex: 2,
    );
  }

  @override
  Future<MediaPage> search(
    AuthenticatedServer account, {
    required String query,
    MediaSearchScope scope = MediaSearchScope.all,
    int startIndex = 0,
    int limit = 40,
    bool forceRefresh = false,
  }) async {
    searchRequests += 1;
    return MediaPage(
      items: [
        MediaItem(id: 'result', name: '$query的结果', kind: MediaItemKind.movie),
      ],
      totalRecordCount: 1,
      nextStartIndex: 1,
    );
  }

  @override
  Future<List<MediaItem>> getRecommendations(
    AuthenticatedServer account, {
    int limit = 6,
    bool forceRefresh = false,
  }) async => const [];

  @override
  Future<List<MediaItem>> getResumeItems(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
    bool excludeActiveSessions = true,
  }) async => const [];

  @override
  Future<List<MediaItem>> getLatestMovies(
    AuthenticatedServer account, {
    int limit = 18,
    String? parentId,
    bool forceRefresh = false,
  }) async => const [];

  @override
  Future<List<MediaItem>> getLatestEpisodes(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
  }) async => const [];
}

AuthenticatedServer _account() {
  return AuthenticatedServer(
    server: DiscoveredServer(
      kind: ServerKind.jellyfin,
      name: '客厅服务器',
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
