import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/library/presentation/media_library_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLibraryService extends MediaLibraryService {
  _FakeLibraryService() : super(Dio());

  @override
  Future<List<MediaItem>> getLibraries(
    AuthenticatedServer account, {
    bool forceRefresh = false,
  }) async {
    return [
      const MediaItem(
        id: 'lib-1',
        name: '电影库',
        kind: MediaItemKind.folder,
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
    return MediaPage(
      items: List.generate(
        30,
        (i) => MediaItem(
          id: 'movie-$i',
          name: '电影 $i',
          kind: MediaItemKind.video,
        ),
      ),
      totalRecordCount: 30,
      nextStartIndex: 30,
    );
  }
}

void main() {
  final account = AuthenticatedServer(
    server: DiscoveredServer(
      kind: ServerKind.jellyfin,
      name: 'Server',
      version: '10.11.0',
      serverId: 'server-1',
      apiBaseUri: Uri.parse('http://127.0.0.1:8096'),
    ),
    userId: 'user-1',
    userName: 'Tester',
    deviceId: 'device-1',
    accessToken: 'token-1',
  );

  testWidgets('MediaLibraryPage density switching updates card sizes', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
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
            body: MediaLibraryPage(
              account: account,
              onGoHome: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card0 = find.byKey(const ValueKey('media-card-artwork-movie-0'));
    expect(card0, findsOneWidget);
    final standardRect = tester.getRect(card0);

    // Tap Compact view
    await tester.tap(find.byTooltip('紧凑视图'));
    await tester.pumpAndSettle();

    final compactRect = tester.getRect(card0);

    // Tap Spacious view
    await tester.tap(find.byTooltip('宽松视图'));
    await tester.pumpAndSettle();

    final spaciousRect = tester.getRect(card0);

    expect(compactRect.width, isNot(equals(standardRect.width)));
    expect(spaciousRect.width, isNot(equals(standardRect.width)));

    expect(compactRect.width, isNot(equals(standardRect.width)));
    expect(spaciousRect.width, isNot(equals(standardRect.width)));
  });
}
