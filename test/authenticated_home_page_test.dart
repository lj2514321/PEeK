import 'dart:async';

import 'package:dio/dio.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/home/presentation/authenticated_home_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final account = _account();

  for (final size in const [Size(375, 812), Size(768, 900), Size(1280, 800)]) {
    testWidgets('lays out the signed-in home at ${size.width.toInt()} pixels', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_homeApp(account, _HomeLibraryService()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-hero')), findsOneWidget);
      expect(find.text('每日推荐一'), findsOneWidget);
      expect(find.text('立即播放'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('daily-recommendation-carousel')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('hero-next')), findsOneWidget);
      await _scrollTo(tester, '最近添加的电影');
      expect(find.text('最近添加的电影'), findsOneWidget);
      await _scrollTo(tester, '最新剧集');
      expect(find.text('最新剧集'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('uses a stable skeleton while the home feed is loading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final release = Completer<void>();

    await tester.pumpWidget(
      _homeApp(account, _HomeLibraryService(release: release.future)),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('home-hero-loading')), findsOneWidget);
    expect(tester.takeException(), isNull);

    release.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-hero')), findsOneWidget);
  });

  testWidgets('moves the daily recommendation carousel manually', (
    tester,
  ) async {
    await tester.pumpWidget(_homeApp(account, _HomeLibraryService()));
    await tester.pumpAndSettle();

    expect(find.text('每日推荐一'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hero-next')));
    await tester.pumpAndSettle();

    expect(find.text('每日推荐二'), findsOneWidget);
    expect(find.text('02 / 03'), findsOneWidget);
  });

  testWidgets('advances the daily recommendation after five seconds', (
    tester,
  ) async {
    await tester.pumpWidget(_homeApp(account, _HomeLibraryService()));
    await tester.pumpAndSettle();

    expect(find.text('每日推荐一'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('每日推荐二'), findsOneWidget);
  });

  testWidgets('does not auto-advance when animations are disabled', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_homeApp(account, _HomeLibraryService()));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 12));

    expect(find.text('每日推荐一'), findsOneWidget);
    expect(find.text('01 / 03'), findsOneWidget);
  });

  testWidgets('refreshes only recommendations after local midnight', (
    tester,
  ) async {
    var now = DateTime(2026, 7, 18, 23, 59, 59, 800);
    final service = _HomeLibraryService();
    await tester.pumpWidget(_homeApp(account, service, clock: () => now));
    await tester.pump();
    await tester.pump();

    expect(service.recommendationRequests, 1);
    expect(find.text('每日推荐一'), findsOneWidget);
    service.recommendations = const [
      MediaItem(
        id: 'recommendation-next-day',
        name: '第二天推荐',
        kind: MediaItemKind.movie,
      ),
    ];
    now = DateTime(2026, 7, 19);

    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();

    expect(service.recommendationRequests, 2);
    expect(service.resumeRequests, 1);
    expect(service.latestMovieRequests, 1);
    expect(service.latestEpisodeRequests, 1);
    expect(find.text('第二天推荐'), findsOneWidget);
  });

  testWidgets('keeps other rails when one home section fails', (tester) async {
    await tester.pumpWidget(
      _homeApp(
        account,
        _HomeLibraryService(
          latestMoviesError: const MediaLibraryException('电影分区失败'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollTo(tester, '最近添加的电影：电影分区失败');
    expect(find.text('最近添加的电影：电影分区失败'), findsOneWidget);
    await _scrollTo(tester, '最新剧集');
    expect(find.text('最新剧集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notifies the shell when the home session expires', (
    tester,
  ) async {
    var expired = false;
    await tester.pumpWidget(
      _homeApp(
        account,
        _HomeLibraryService(
          resumeError: const MediaLibraryException(
            '登录已失效',
            authenticationExpired: true,
          ),
        ),
        onSessionExpired: () async => expired = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(expired, isTrue);
  });
}

Future<void> _scrollTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    320,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Widget _homeApp(
  AuthenticatedServer account,
  MediaLibraryService service, {
  Future<void> Function()? onSessionExpired,
  DateTime Function()? clock,
}) {
  return ProviderScope(
    overrides: [mediaLibraryProvider.overrideWithValue(service)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        backgroundColor: AppColors.canvas,
        body: AuthenticatedHomePage(
          account: account,
          onOpenLibrary: () {},
          onSessionExpired: onSessionExpired ?? () async {},
          clock: clock,
        ),
      ),
    ),
  );
}

class _HomeLibraryService extends MediaLibraryService {
  _HomeLibraryService({this.release, this.latestMoviesError, this.resumeError})
    : super(Dio());

  final Future<void>? release;
  final MediaLibraryException? latestMoviesError;
  final MediaLibraryException? resumeError;
  List<MediaItem> recommendations = const [
    MediaItem(
      id: 'recommendation-1',
      name: '每日推荐一',
      kind: MediaItemKind.movie,
      overview: '今晚值得打开的一部电影。',
      productionYear: 2026,
      runTime: Duration(minutes: 118),
    ),
    MediaItem(
      id: 'recommendation-2',
      name: '每日推荐二',
      kind: MediaItemKind.movie,
      productionYear: 2025,
    ),
    MediaItem(
      id: 'recommendation-3',
      name: '每日推荐三',
      kind: MediaItemKind.episode,
      seriesName: '示例剧集',
      parentIndexNumber: 2,
      indexNumber: 4,
    ),
  ];
  int recommendationRequests = 0;
  int resumeRequests = 0;
  int latestMovieRequests = 0;
  int latestEpisodeRequests = 0;

  Future<void> _wait() async {
    if (release != null) await release;
  }

  @override
  Future<List<MediaItem>> getRecommendations(
    AuthenticatedServer account, {
    int limit = 6,
    bool forceRefresh = false,
  }) async {
    await _wait();
    recommendationRequests += 1;
    return recommendations;
  }

  @override
  Future<List<MediaItem>> getResumeItems(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
  }) async {
    await _wait();
    resumeRequests += 1;
    if (resumeError != null) throw resumeError!;
    return const [
      MediaItem(
        id: 'resume-1',
        name: '续播电影',
        kind: MediaItemKind.movie,
        overview: '一段用于验证首页主舞台的影片简介。',
        productionYear: 2026,
        runTime: Duration(hours: 2),
        resumePosition: Duration(minutes: 42),
      ),
      MediaItem(
        id: 'resume-2',
        name: '另一部影片',
        kind: MediaItemKind.movie,
        runTime: Duration(minutes: 90),
        resumePosition: Duration(minutes: 10),
      ),
    ];
  }

  @override
  Future<List<MediaItem>> getLatestMovies(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
  }) async {
    await _wait();
    latestMovieRequests += 1;
    if (latestMoviesError != null) throw latestMoviesError!;
    return const [
      MediaItem(
        id: 'movie-1',
        name: '最新电影',
        kind: MediaItemKind.movie,
        productionYear: 2026,
      ),
    ];
  }

  @override
  Future<List<MediaItem>> getLatestEpisodes(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
  }) async {
    await _wait();
    latestEpisodeRequests += 1;
    return const [
      MediaItem(
        id: 'episode-1',
        name: '最新一集',
        kind: MediaItemKind.episode,
        seriesName: '示例剧集',
        parentIndexNumber: 1,
        indexNumber: 3,
      ),
    ];
  }
}

AuthenticatedServer _account() {
  return AuthenticatedServer(
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
}
