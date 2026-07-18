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
}

class _FakeLibraryService extends MediaLibraryService {
  _FakeLibraryService() : super(Dio());

  final requestedStartIndexes = <int>[];
  final requestedParentIds = <String>[];

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
    bool forceRefresh = false,
  }) async {
    requestedStartIndexes.add(startIndex);
    requestedParentIds.add(parentId);
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
}
