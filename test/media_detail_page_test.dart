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
}

class _FakeDetailService extends MediaLibraryService {
  _FakeDetailService() : super(Dio());

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
}
