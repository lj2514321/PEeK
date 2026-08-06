import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/people/presentation/actors_page.dart';
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
    testWidgets('lays out actors at ${size.width.toInt()} pixels', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaLibraryProvider.overrideWithValue(_FakeActorsService()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: ActorsPage(account: account, onOpenLibrary: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('演员列表'), findsOneWidget);
      expect(find.text('演员 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loads another page near the end', (tester) async {
    tester.view.physicalSize = const Size(800, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeActorsService(total: 80);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ActorsPage(account: account, onOpenLibrary: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const PageStorageKey('actors-scroll-view')),
      const Offset(0, -10000),
    );
    await tester.pumpAndSettle();

    expect(service.requestedStartIndexes, contains(60));
    expect(find.text('演员 61'), findsOneWidget);
  });

  testWidgets('guides an unauthenticated user to the media library', (
    tester,
  ) async {
    var openedLibrary = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaLibraryProvider.overrideWithValue(_FakeActorsService()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ActorsPage(
              account: null,
              onOpenLibrary: () => openedLibrary = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后浏览演员'), findsOneWidget);
    await tester.tap(find.text('去媒体库看看'));
    expect(openedLibrary, isTrue);
  });

  testWidgets('shows an empty message when the server has no actors', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaLibraryProvider.overrideWithValue(_FakeActorsService(total: 0)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ActorsPage(account: account, onOpenLibrary: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('媒体库中暂无演员信息'), findsOneWidget);
  });

  testWidgets('recovers from a failed initial load', (tester) async {
    final service = _FakeActorsService(failFirstLoad: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ActorsPage(account: account, onOpenLibrary: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂时无法读取演员'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();

    expect(service.loadAttempts, 2);
    expect(find.text('演员 1'), findsOneWidget);
  });

  testWidgets('opens the person works page from an actor card', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaLibraryProvider.overrideWithValue(_FakeActorsService(total: 2)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ActorsPage(account: account, onOpenLibrary: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('actor-actor-1')));
    await tester.pumpAndSettle();

    expect(find.text('媒体库中共 1 部相关作品'), findsOneWidget);
    expect(find.text('代表作品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeActorsService extends MediaLibraryService {
  _FakeActorsService({this.total = 65, this.failFirstLoad = false})
    : super(Dio());

  final int total;
  final bool failFirstLoad;
  final requestedStartIndexes = <int>[];
  int loadAttempts = 0;

  @override
  Future<MediaPage> getActors(
    AuthenticatedServer account, {
    int startIndex = 0,
    int limit = 60,
    bool forceRefresh = false,
  }) async {
    loadAttempts++;
    if (failFirstLoad && loadAttempts == 1) {
      throw const MediaLibraryException('服务器暂时不可用。');
    }
    requestedStartIndexes.add(startIndex);
    final end = (startIndex + limit).clamp(0, total);
    return MediaPage(
      items: startIndex >= total
          ? const []
          : List.generate(
              end - startIndex,
              (index) => MediaItem(
                id: 'actor-${startIndex + index + 1}',
                name: '演员 ${startIndex + index + 1}',
                kind: MediaItemKind.person,
              ),
            ),
      totalRecordCount: total,
      nextStartIndex: end,
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
    return MediaPage(
      items: [MediaItem(id: 'work-1', name: '代表作品', kind: MediaItemKind.movie)],
      totalRecordCount: 1,
      nextStartIndex: 1,
    );
  }
}
