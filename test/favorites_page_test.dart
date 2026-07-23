import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/favorites/presentation/favorites_page.dart';
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
    testWidgets('lays out favorites at ${size.width.toInt()} pixels', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaLibraryProvider.overrideWithValue(_FakeFavoritesService()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: FavoritesPage(
                account: account,
                onGoHome: () {},
                onOpenLibrary: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('收藏电影 1'), findsOneWidget);
      expect(find.byTooltip('从收藏移除'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('removes a favorite and supports undo', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeFavoritesService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: FavoritesPage(
              account: account,
              onGoHome: () {},
              onOpenLibrary: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('remove-favorite-favorite-1')));
    await tester.pumpAndSettle();

    expect(service.favoriteValues, [false]);
    expect(find.text('收藏电影 1'), findsNothing);
    expect(find.text('已从收藏移除《收藏电影 1》'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(service.favoriteValues, [false, true]);
    expect(find.text('收藏电影 1'), findsOneWidget);
    expect(find.text('已恢复收藏'), findsOneWidget);
  });

  testWidgets('loads another page near the end', (tester) async {
    tester.view.physicalSize = const Size(800, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeFavoritesService(total: 80);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mediaLibraryProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: FavoritesPage(
              account: account,
              onGoHome: () {},
              onOpenLibrary: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const PageStorageKey('favorites-scroll-view')),
      const Offset(0, -10000),
    );
    await tester.pumpAndSettle();

    expect(service.requestedStartIndexes, contains(60));
    expect(find.text('收藏电影 61'), findsOneWidget);
  });

  testWidgets('guides an empty collection back to the media library', (
    tester,
  ) async {
    var openedLibrary = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaLibraryProvider.overrideWithValue(
            _FakeFavoritesService(total: 0),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: FavoritesPage(
              account: account,
              onGoHome: () {},
              onOpenLibrary: () => openedLibrary = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('收藏还是空的'), findsOneWidget);
    await tester.tap(find.text('去媒体库看看'));
    expect(openedLibrary, isTrue);
  });
}

class _FakeFavoritesService extends MediaLibraryService {
  _FakeFavoritesService({this.total = 65}) : super(Dio());

  final int total;
  final requestedStartIndexes = <int>[];
  final favoriteValues = <bool>[];

  @override
  Future<MediaPage> getFavoriteItems(
    AuthenticatedServer account, {
    int startIndex = 0,
    int limit = 60,
    bool forceRefresh = false,
  }) async {
    requestedStartIndexes.add(startIndex);
    final end = (startIndex + limit).clamp(0, total);
    return MediaPage(
      items: startIndex >= total
          ? const []
          : List.generate(
              end - startIndex,
              (index) => MediaItem(
                id: 'favorite-${startIndex + index + 1}',
                name: '收藏电影 ${startIndex + index + 1}',
                kind: MediaItemKind.movie,
                productionYear: 2026,
                runTime: const Duration(minutes: 108),
                favorite: true,
              ),
            ),
      totalRecordCount: total,
      nextStartIndex: end,
    );
  }

  @override
  Future<void> setFavorite(
    AuthenticatedServer account,
    String itemId, {
    required bool favorite,
  }) async {
    favoriteValues.add(favorite);
  }
}
