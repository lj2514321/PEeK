# 演员浏览（第 6 导航项）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增跨媒体库的「演员」导航页：分页展示当前服务器全部演员（`PersonTypes=Actor`），点击卡片进入现有 `PersonWorksPage` 查看其作品。

**Architecture:** 服务层在现有 `MediaLibraryService` 增加 `getActors()`（复用 `_requestPage`/`_parseItem` 管道与 JSON 缓存）；展示层新建 `features/people/presentation/actors_page.dart`，结构完全仿照 `FavoritesPage`（分页、账户切换重置、空态/错误态）；`home_shell.dart` 追加第 6 个 destination 与 `Ctrl+6`。`PersonWorksPage`/`MediaDetailPage` 零改动，仅新增入口。

**Tech Stack:** Flutter 3.44.6 / Dart ^3.12.2、flutter_riverpod 3、Dio 5、现有 `MediaLibraryService` 与组件（`PeekMediaImage`、`AmbientBackdrop`、`AppGlass`）。

## Global Constraints

- 格式检查命令：`dart format --output=none --set-exit-if-changed lib test tool`；CI 对每次 push/PR 执行格式检查 + `flutter analyze` + `flutter test`。
- 仅远程 Jellyfin/Emby；仅 `Actor` 角色（查询参数 `PersonTypes=Actor`）。本地媒体库不参与。
- 不改动 `PersonWorksPage`、`MediaDetailPage`；不引入 gateway/Repository 分层。
- 现有快捷键 `Ctrl+1`~`Ctrl+5` 保持不变；新增 `Ctrl+6` 切到演员页。
- 新页面 UI 文案为中文，与全应用语气一致。
- 测试沿用现有模式：服务测试用 Dio interceptor 捕获请求并返回假响应；页面测试用继承 `MediaLibraryService` 的假服务 + `mediaLibraryProvider.overrideWithValue`。

---

### Task 1: 服务层 `MediaLibraryService.getActors()`

**Files:**
- Modify: `lib/src/features/servers/data/media_library_service.dart`（在 `getFavoriteItems` 之后、`search` 之前插入新方法）
- Test: `test/media_library_service_test.dart`（文件末尾追加 3 个 test）

**Interfaces:**
- Consumes: 现有 `AuthenticatedServer`（`server.apiBaseUri`、`userId`、`accessToken`）、`_requestPage`、`_itemPageCacheAge`。
- Produces: `Future<MediaPage> getActors(AuthenticatedServer account, {int startIndex = 0, int limit = 60, bool forceRefresh = false})` —— 返回 `MediaPage`，其中 `items` 是 `MediaItemKind.person` 类型的 `MediaItem`（`imageUri` 为 `Items/{id}/Images/Primary?tag=...`，`imageHeaders` 带 `X-Emby-Token`）。

- [ ] **Step 1: 追加服务测试（参数与解析）**

在 `test/media_library_service_test.dart` 的 `main()` 内、`account` 定义之后追加：

```dart
  test('loads actors across libraries with person type filtering', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'TotalRecordCount': 12,
                  'Items': [
                    {
                      'Id': 'person-1',
                      'Name': '演员甲',
                      'Type': 'Person',
                      'ImageTags': {'Primary': 'avatar-tag'},
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    final page = await MediaLibraryService(dio).getActors(account);

    expect(request?.uri.path, '/Users/user-id/Items');
    expect(request?.uri.queryParameters['Recursive'], 'true');
    expect(request?.uri.queryParameters['IncludeItemTypes'], 'Person');
    expect(request?.uri.queryParameters['PersonTypes'], 'Actor');
    expect(request?.uri.queryParameters['SortBy'], 'SortName');
    expect(request?.uri.queryParameters['SortOrder'], 'Ascending');
    expect(request?.uri.queryParameters['ImageTypeLimit'], '1');
    expect(request?.uri.queryParameters['EnableImageTypes'], 'Primary');
    expect(request?.uri.queryParameters['StartIndex'], '0');
    expect(request?.uri.queryParameters['Limit'], '60');
    expect(request?.headers['X-Emby-Token'], 'secret-token');
    expect(page.totalRecordCount, 12);
    expect(page.nextStartIndex, 1);
    expect(page.hasMore, isTrue);
    expect(page.items.single.kind, MediaItemKind.person);
    expect(page.items.single.name, '演员甲');
    expect(page.items.single.imageUri?.path, '/Items/person-1/Images/Primary');
    expect(page.items.single.imageUri?.queryParameters['tag'], 'avatar-tag');
    expect(page.items.single.imageHeaders['X-Emby-Token'], 'secret-token');
  });

  test('passes start index and limit through the actors query', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {'TotalRecordCount': 0, 'Items': []},
              ),
            );
          },
        ),
      );

    final page = await MediaLibraryService(
      dio,
    ).getActors(account, startIndex: 60, limit: 40);

    expect(request?.uri.queryParameters['StartIndex'], '60');
    expect(request?.uri.queryParameters['Limit'], '40');
    expect(page.hasMore, isFalse);
  });

  test('serves cached actors and refreshes them in the background', () async {
    var requestCount = 0;
    final releaseRefresh = Completer<void>();
    final refreshStarted = Completer<void>();
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requestCount++;
            if (requestCount > 1) {
              if (!refreshStarted.isCompleted) refreshStarted.complete();
              await releaseRefresh.future;
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'TotalRecordCount': 1,
                  'Items': [
                    {
                      'Id': 'person-cache',
                      'Name': requestCount == 1 ? '缓存演员' : '刷新演员',
                      'Type': 'Person',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
    final service = MediaLibraryService(dio, MemoryMediaCacheStore());

    expect((await service.getActors(account)).single.name, '缓存演员');
    final cached = await service
        .getActors(account)
        .timeout(const Duration(milliseconds: 100));

    expect(cached.single.name, '缓存演员');
    await refreshStarted.future.timeout(const Duration(seconds: 1));
    expect(requestCount, 2);
    releaseRefresh.complete();
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/media_library_service_test.dart`
Expected: FAIL —— `getActors` 不存在（编译错误 "The method 'getActors' isn't defined"）。

- [ ] **Step 3: 实现 `getActors`**

在 `media_library_service.dart` 的 `getFavoriteItems` 方法（约 122 行结束）与 `search` 方法之间插入：

```dart
  Future<MediaPage> getActors(
    AuthenticatedServer account, {
    int startIndex = 0,
    int limit = 60,
    bool forceRefresh = false,
  }) async {
    final uri =
        _appendPath(
          account.server.apiBaseUri,
          'Users/${account.userId}/Items',
        ).replace(
          queryParameters: {
            'Recursive': 'true',
            'IncludeItemTypes': 'Person',
            'PersonTypes': 'Actor',
            'SortBy': 'SortName',
            'SortOrder': 'Ascending',
            'ImageTypeLimit': '1',
            'EnableImageTypes': 'Primary',
            'StartIndex': '$startIndex',
            'Limit': '$limit',
            'EnableTotalRecordCount': 'true',
          },
        );
    return _requestPage(
      uri,
      account,
      startIndex: startIndex,
      cacheAge: _itemPageCacheAge,
      forceRefresh: forceRefresh,
    );
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/media_library_service_test.dart`
Expected: PASS（含原有测试与新 3 个测试）。

- [ ] **Step 5: 提交**

```bash
git add lib/src/features/servers/data/media_library_service.dart test/media_library_service_test.dart
git commit -m "feat: add cross-library actors query to media library service"
```

---

### Task 2: `ActorsPage` 页面

**Files:**
- Create: `lib/src/features/people/presentation/actors_page.dart`
- Test: `test/actors_page_test.dart`

**Interfaces:**
- Consumes: `mediaLibraryProvider.getActors(...)`（Task 1 产出）、`PersonWorksPage(account:, person:, onOpen:)`、`MediaDetailPage(account:, initialItem:)`、`SessionExpiryEvent`（不经由本页导入，仅调用 `onSessionExpired` 回调）。
- Produces: `ActorsPage`（`account: AuthenticatedServer?`、`onOpenLibrary: VoidCallback`、`onSessionExpired: VoidCallback?`），公开 `ActorsPageState`（含 `scrollToTop()`），供 Task 3 的 `GlobalKey<ActorsPageState>` 使用。

- [ ] **Step 1: 写页面测试**

创建 `test/actors_page_test.dart`（仿 `favorites_page_test.dart`）：

```dart
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
              body: ActorsPage(
                account: account,
                onOpenLibrary: () {},
              ),
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
      items: [
        MediaItem(id: 'work-1', name: '代表作品', kind: MediaItemKind.movie),
      ],
      totalRecordCount: 1,
      nextStartIndex: 1,
    );
  }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/actors_page_test.dart`
Expected: FAIL —— 找不到 `actors_page.dart`（编译错误）。

- [ ] **Step 3: 实现 `ActorsPage`**

创建 `lib/src/features/people/presentation/actors_page.dart`，完整内容（结构仿 `FavoritesPage` + `PersonWorksPage`）：

```dart
import 'package:embyplayer/src/app/app_chrome.dart';
import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/details/presentation/person_works_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActorsPage extends ConsumerStatefulWidget {
  const ActorsPage({
    super.key,
    required this.account,
    required this.onOpenLibrary,
    this.onSessionExpired,
  });

  final AuthenticatedServer? account;
  final VoidCallback onOpenLibrary;
  final VoidCallback? onSessionExpired;

  @override
  ConsumerState<ActorsPage> createState() => ActorsPageState();
}

class ActorsPageState extends ConsumerState<ActorsPage> {
  static const _pageSize = 60;

  final _scrollController = ScrollController();
  List<MediaItem> _items = const [];
  int _totalItemCount = 0;
  int _nextStartIndex = 0;
  int _requestGeneration = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _paginationError;

  bool get _hasMore => _items.isNotEmpty && _nextStartIndex < _totalItemCount;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearEnd);
    if (widget.account != null) {
      Future<void>.microtask(_loadActors);
    }
  }

  @override
  void didUpdateWidget(covariant ActorsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.account;
    final current = widget.account;
    if (previous?.userId != current?.userId ||
        previous?.server.serverId != current?.server.serverId) {
      if (current == null) {
        _requestGeneration++;
        setState(() {
          _items = const [];
          _totalItemCount = 0;
          _nextStartIndex = 0;
          _error = null;
          _paginationError = null;
        });
      } else {
        _loadActors();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void scrollToTop() {
    if (!_scrollController.hasClients) return;
    final duration = AppMotion.responsive(context, AppMotion.standard);
    if (duration == Duration.zero) {
      _scrollController.jumpTo(0);
      return;
    }
    _scrollController.animateTo(
      0,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadActors({bool forceRefresh = false}) async {
    final account = widget.account;
    if (account == null) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _paginationError = null;
    });
    try {
      final page = await ref
          .read(mediaLibraryProvider)
          .getActors(account, limit: _pageSize, forceRefresh: forceRefresh);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _items = page.items;
        _totalItemCount = page.totalRecordCount;
        _nextStartIndex = page.nextStartIndex;
      });
    } on MediaLibraryException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      if (_items.isEmpty) {
        setState(() => _error = error.message);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('刷新演员失败：${error.message}')));
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _loadMoreNearEnd() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 700) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final account = widget.account;
    if (account == null ||
        _loading ||
        _loadingMore ||
        _nextStartIndex >= _totalItemCount) {
      return;
    }
    final generation = _requestGeneration;
    setState(() {
      _loadingMore = true;
      _paginationError = null;
    });
    try {
      final page = await ref
          .read(mediaLibraryProvider)
          .getActors(account, startIndex: _nextStartIndex, limit: _pageSize);
      if (!mounted || generation != _requestGeneration) return;
      final knownIds = _items.map((item) => item.id).toSet();
      setState(() {
        _items = [
          ..._items,
          ...page.items.where((item) => knownIds.add(item.id)),
        ];
        _totalItemCount = page.totalRecordCount;
        _nextStartIndex = page.nextStartIndex;
      });
    } on MediaLibraryException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      setState(() => _paginationError = error.message);
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _openActor(MediaItem item) async {
    final account = widget.account;
    if (account == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => PersonWorksPage(
          account: account,
          person: MediaPerson(
            id: item.id,
            name: item.name,
            type: 'Actor',
            imageUri: item.imageUri,
            imageHeaders: item.imageHeaders,
          ),
          onOpen: _openWork,
        ),
      ),
    );
  }

  void _openWork(MediaItem item) {
    final account = widget.account;
    if (account == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            MediaDetailPage(account: account, initialItem: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackdrop(
        child: CustomScrollView(
          key: const PageStorageKey('actors-scroll-view'),
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              backgroundColor: AppColors.glassStrong.withValues(alpha: 0.92),
              title: const Text('演员列表'),
              actions: [
                if (defaultTargetPlatform == TargetPlatform.windows)
                  const SizedBox(width: AppChrome.windowControlsWidth),
              ],
            ),
            if (widget.account == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ActorsMessage(
                  icon: Icons.people_outline_rounded,
                  title: '登录后浏览演员',
                  message: '连接并登录 Jellyfin 或 Emby 后，服务器媒体库中的演员会集中显示在这里。',
                  actionLabel: '去媒体库看看',
                  onAction: widget.onOpenLibrary,
                ),
              )
            else if (_loading && _items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ActorsMessage(
                  icon: Icons.cloud_off_rounded,
                  title: '暂时无法读取演员',
                  message: _error!,
                  actionLabel: '重新加载',
                  onAction: () => _loadActors(forceRefresh: true),
                ),
              )
            else if (_items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _ActorsMessage(
                  icon: Icons.person_search_rounded,
                  title: '媒体库中暂无演员信息',
                  message: '服务器没有返回任何演员数据。',
                ),
              )
            else
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final columns = switch (width) {
                    < 520 => 2,
                    < 760 => 3,
                    < 1000 => 4,
                    < 1260 => 5,
                    _ => 6,
                  };
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 22,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _ActorCard(
                          item: item,
                          onOpen: () => _openActor(item),
                        );
                      },
                    ),
                  );
                },
              ),
            if (_items.isNotEmpty &&
                (_loadingMore || _paginationError != null || _hasMore))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  child: Center(
                    child: _loadingMore
                        ? const SizedBox.square(
                            dimension: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : TextButton.icon(
                            onPressed: _loadMore,
                            icon: Icon(
                              _paginationError == null
                                  ? Icons.expand_more_rounded
                                  : Icons.refresh_rounded,
                            ),
                            label: Text(
                              _paginationError == null ? '加载更多' : '加载失败，点击重试',
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActorCard extends StatelessWidget {
  const _ActorCard({required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '查看 ${item.name} 的作品',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Material(
              color: AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('actor-${item.id}'),
                onTap: onOpen,
                child: Center(
                  child: SizedBox.square(
                    dimension: 96,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(48),
                      child: PeekMediaImage(
                        uri: item.imageUri,
                        headers: item.imageHeaders,
                        kind: PeekMediaImageKind.person,
                        placeholderBackground: AppColors.surfaceHigh,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ActorsMessage extends StatelessWidget {
  const _ActorsMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 46, color: AppColors.textTertiary),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  height: 1.5,
                ),
              ),
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/actors_page_test.dart`
Expected: PASS（6 个测试）。若 `peek_motion.dart` 的 `AppMotion` 引用与收藏页写法有出入，以 `favorites_page.dart` 的 `scrollToTop()` 实现为准对齐。

- [ ] **Step 5: 提交**

```bash
git add lib/src/features/people/presentation/actors_page.dart test/actors_page_test.dart
git commit -m "feat: add actors browsing page with person works entry"
```

---

### Task 3: `home_shell` 导航接线

**Files:**
- Modify: `lib/src/features/home/presentation/home_shell.dart`（4 处：字段、destinations、快捷键、页面构建 + `_selectDestination`）
- Modify: `test/home_shell_interaction_test.dart`（`_ShellLibraryService` 加 `getActors` 覆写，追加 3 个测试）

**Interfaces:**
- Consumes: `ActorsPage`、`ActorsPageState.scrollToTop()`（Task 2 产出）。
- Produces: 第 6 个 destination「演员」（index 5），`Ctrl+6` 快捷键；`Ctrl+1~5` 不变。

- [ ] **Step 1: 写接线测试**

在 `test/home_shell_interaction_test.dart` 追加 import：

```dart
import 'package:flutter/services.dart';
```

在 `_ShellLibraryService` 中新增字段与方法：

```dart
  int actorRequests = 0;

  @override
  Future<MediaPage> getActors(
    AuthenticatedServer account, {
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
```

在 `main()` 中追加测试（复用现有 `_account()` 与 4 个 provider override 的 pump 结构，可在文件内抽一个本地 `pumpShell` 辅助函数，或直接复制现有 pump 块）：

```dart
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

  testWidgets('switches to actors with Ctrl+6', (tester) async {
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
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit6);
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/home_shell_interaction_test.dart`
Expected: FAIL —— 新测试找不到「演员」destination。

- [ ] **Step 3: 实现接线**

`home_shell.dart` 4 处修改：

3a. 字段区（`_searchPageKey` 声明之后）：

```dart
  final _actorsPageKey = GlobalKey<ActorsPageState>();
```

3b. `_destinations` 末尾追加一项：

```dart
    _AppDestination('演员', Icons.people_outline_rounded, Icons.people_rounded),
```

3c. `CallbackShortcuts` bindings 中 `digit5` 之后追加：

```dart
        const SingleActivator(LogicalKeyboardKey.digit6, control: true): () {
          _selectDestination(5);
        },
```

3d. `_selectDestination` 的重复选择 switch 中 `case 2` 之后追加：

```dart
        case 5:
          _actorsPageKey.currentState?.scrollToTop();
          return;
```

3e. 页面构建：在 index 4 的 `_KeepAliveDestination`（`ServerAccountsPage`）块之后追加：

```dart
                                    _KeepAliveDestination(
                                      active: _selectedIndex == 5,
                                      child: _visitedDestinations.contains(5)
                                          ? ActorsPage(
                                              key: _actorsPageKey,
                                              account: _authenticatedServer,
                                              onOpenLibrary: () =>
                                                  _selectDestination(1),
                                              onSessionExpired:
                                                  _handleSessionExpired,
                                            )
                                          : const SizedBox.shrink(),
                                    ),
```

imports 追加：

```dart
import 'package:embyplayer/src/features/people/presentation/actors_page.dart';
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/home_shell_interaction_test.dart`
Expected: PASS（原有 2 个 + 新增 3 个）。

- [ ] **Step 5: 提交**

```bash
git add lib/src/features/home/presentation/home_shell.dart test/home_shell_interaction_test.dart
git commit -m "feat: add actors destination and Ctrl+6 shortcut to navigation shell"
```

---

### Task 4: 文档同步

**Files:**
- Modify: `README.md`（3 处）
- Modify: `docs/ARCHITECTURE.md`（2 处）
- Verify: `CLAUDE.md`（无需改动——不含导航数量描述）

- [ ] **Step 1: README.md**

1a. 「功能概览」表格中「搜索与详情」行之后追加：

```markdown
| 演员 | 跨媒体库浏览演员，点击进入其全部作品与详情 |
```

1b. 「主界面」快捷键表格 `Ctrl + 5` 行之后追加：

```markdown
| `Ctrl + 6` | 切换演员 |
```

1c. 「项目结构」features 树中 `favorites/` 行之后追加：

```markdown
    ├── people/             # 演员浏览
```

- [ ] **Step 2: docs/ARCHITECTURE.md**

2a. 导航段落中「小屏使用五项底部导航」改为「小屏使用六项底部导航」。

2b. 「收藏和已观看状态」段落之后新增一段：

```markdown
演员页通过 `IncludeItemTypes=Person&PersonTypes=Actor` 的跨库递归查询聚合当前服务器演员，独立分页并按名称排序；点击演员复用作品页与详情页。演员浏览仅作用于远程媒体库，本地媒体库不参与。
```

- [ ] **Step 3: 确认 CLAUDE.md 无需改动**

Run: `grep -n "导航\|destination\|5 项\|五" CLAUDE.md`
Expected: 无命中（CLAUDE.md 不含导航数量描述）。若有命中则同步更新。

- [ ] **Step 4: 提交**

```bash
git add README.md docs/ARCHITECTURE.md
git commit -m "docs: document actors browsing destination"
```

---

### Task 5: 全量验证

**Files:** 无新增。

- [ ] **Step 1: 格式检查**

Run: `dart format --output=none --set-exit-if-changed lib test tool`
Expected: 通过（若报未格式化，运行 `dart format lib test tool` 后重新检查）。

- [ ] **Step 2: 静态分析**

Run: `flutter analyze`
Expected: 无 error/warning。

- [ ] **Step 3: 全量测试**

Run: `flutter test`
Expected: 全部通过（原有 35 个测试文件 + 新增 `actors_page_test.dart`，`home_shell_interaction_test.dart` 与 `media_library_service_test.dart` 增量）。

- [ ] **Step 4: 提交收尾**

```bash
git status
git add -A
git commit -m "chore: finalize actors browsing feature" --allow-empty-message 2>/dev/null || true
```

若 Step 1–3 全部通过且工作区无其他改动，跳过本次提交。
