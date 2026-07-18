import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/storage/search_history_store.dart';
import 'package:embyplayer/src/features/search/presentation/media_search_page.dart';
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

  for (final size in const [Size(375, 812), Size(1280, 900)]) {
    testWidgets(
      'search page lays out results at ${size.width.toInt()} pixels',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _testApp(account: account, service: _FakeSearchService()),
        );
        await tester.enterText(
          find.byKey(const ValueKey('media-search-field')),
          '示例',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(find.text('示例电影'), findsOneWidget);
        expect(find.text('示例演员'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('opens a person result and displays their filmography', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeSearchService();

    await tester.pumpWidget(_testApp(account: account, service: service));
    await tester.enterText(
      find.byKey(const ValueKey('media-search-field')),
      '示例',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看作品'));
    await tester.tap(find.text('查看作品'));
    await tester.pumpAndSettle();

    expect(service.requestedPersonIds, ['person-id']);
    expect(find.text('示例演员 的相关作品'), findsOneWidget);
    expect(find.text('演员作品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows connection guidance without an authenticated server', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(account: null, service: _FakeSearchService()),
    );

    expect(find.text('连接服务器后开始搜索'), findsOneWidget);
    expect(find.text('返回并连接服务器'), findsOneWidget);
  });
}

Widget _testApp({
  required AuthenticatedServer? account,
  required MediaLibraryService service,
}) {
  return ProviderScope(
    overrides: [
      mediaLibraryProvider.overrideWithValue(service),
      searchHistoryStoreProvider.overrideWithValue(MemorySearchHistoryStore()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: MediaSearchPage(account: account, onGoHome: () {}),
      ),
    ),
  );
}

class _FakeSearchService extends MediaLibraryService {
  _FakeSearchService() : super(Dio());

  final requestedPersonIds = <String>[];

  @override
  Future<MediaPage> search(
    AuthenticatedServer account, {
    required String query,
    MediaSearchScope scope = MediaSearchScope.all,
    int startIndex = 0,
    int limit = 40,
    bool forceRefresh = false,
  }) async {
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
        MediaItem(id: 'credit-id', name: '演员作品', kind: MediaItemKind.movie),
      ],
      totalRecordCount: 1,
      nextStartIndex: 1,
    );
  }
}
