// ignore_for_file: avoid_print

import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/library/presentation/media_library_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/gestures.dart';
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
    return List.generate(
      5,
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
        80,
        (i) => MediaItem(
          id: 'item-$parentId-$startIndex-$i',
          name: '条目 $i ($parentId)',
          kind: MediaItemKind.video,
        ),
      ),
      totalRecordCount: 200,
      nextStartIndex: startIndex + 60,
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

  testWidgets('MediaLibraryPage scroll behavior after switching library', (
    tester,
  ) async {
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
            body: MediaLibraryPage(account: account, onGoHome: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial load
    expect(find.text('条目 0 (library-0)'), findsOneWidget);

    // Tap on library 2 in the selector
    print('[TEST] Selecting 媒体库 2...');
    await tester.tap(find.text('打开媒体库').first);
    await tester.pumpAndSettle();

    expect(find.text('条目 0 (library-1)'), findsOneWidget);

    // Now find the scrollable
    final scrollables = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .toList();
    final outer = scrollables.firstWhere(
      (s) =>
          s.widget.axisDirection == AxisDirection.down &&
          s.position is SmoothScrollPosition,
    );
    final position = outer.position as SmoothScrollPosition;
    print(
      '[TEST] Outer scrollable after switch: pixels=${position.pixels}, maxExtent=${position.maxScrollExtent}',
    );

    // Simulate mouse wheel scroll over a card
    final card0 = find.text('条目 0 (library-1)');
    final cardRect = tester.getRect(card0);
    print('[TEST] Card 0 rect: $cardRect');

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(cardRect.center));
    await tester.pump();

    print('[TEST] Sending mouse wheel scroll (dy = 120)');
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();
    print('[TEST] Frame 1 (16ms): pixels = ${position.pixels}');

    await tester.pump(const Duration(milliseconds: 32));
    print('[TEST] Frame 3 (48ms): pixels = ${position.pixels}');

    await tester.pump(const Duration(milliseconds: 100));
    print('[TEST] Frame 9 (148ms): pixels = ${position.pixels}');

    await tester.pump(const Duration(milliseconds: 250));
    print('[TEST] Settle (398ms): pixels = ${position.pixels}');

    expect(position.pixels, greaterThan(0));
  });
}
