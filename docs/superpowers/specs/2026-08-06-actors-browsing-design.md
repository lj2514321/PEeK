# 演员浏览（第 6 导航项）设计

日期：2026-08-06
状态：已批准

## 目标

新增跨媒体库的「演员」浏览入口：显示当前服务器全部媒体库中的演员（仅 Actor 角色、仅远程数据），点击演员卡片进入其作品列表。作品列表复用现有 `PersonWorksPage`，从作品可进入详情与播放。

## 范围与边界

- 仅远程 Jellyfin/Emby 服务器；本地媒体库不参与（本地文件无演员元数据）。
- 仅 `Actor` 角色，不含导演、编剧等其他人物类型。
- 不引入 gateway / Repository 分层重构（ROADMAP 已有规划，不在本轮）。
- 不改动 `PersonWorksPage` 与 `MediaDetailPage`，仅新增入口。
- 不做按媒体库筛选演员（聚合展示，YAGNI）。

## 方案决策

对比过三个方案：新导航项 / 媒体库页内 tab / 媒体库页入口按钮。

**选定：新增第 6 个导航项「演员」**。理由：

- 媒体库页语义是「选中一个库 → 文件夹下钻 → 筛选」，与「跨全部库聚合人物」作用域矛盾；该页已 1900+ 行，不宜再加重。
- 收藏页已是「跨库聚合 + 独立分页」的成熟先例，演员页结构与之完全同构，可套模板。
- 导航扩展成本低：`_destinations` 加一项 + `Ctrl+6`，PageView 按需创建模式天然支持。

## 服务层

`MediaLibraryService` 新增方法（仿 `getFavoriteItems`）：

```dart
Future<MediaPage> getActors(
  AuthenticatedServer account, {
  int startIndex = 0,
  int limit = 60,
  bool forceRefresh = false,
}) async
```

查询：`Users/{userId}/Items`，参数：

- `Recursive=true`
- `IncludeItemTypes=Person`
- `PersonTypes=Actor`（Jellyfin 与 Emby 均支持）
- `SortBy=SortName`、`SortOrder=Ascending`
- `ImageTypeLimit=1`、`EnableImageTypes=Primary`
- `EnableTotalRecordCount=true`、`StartIndex`、`Limit`

复用现有 `_requestPage` / `_parseItem` 管道（person 类型与 Primary 头像解析已支持）。缓存 `_itemPageCacheAge`（10 分钟）。演员无年份/简介，不带 `Fields`。

## 页面

新 feature 目录 `lib/src/features/people/`（仅 presentation 层），文件 `presentation/actors_page.dart`：

- `ActorsPage extends ConsumerStatefulWidget`，构造参数 `{account, onOpenLibrary}`（仿 `FavoritesPage`）。
- 分页加载：`_loadInitial` / `_loadMore`，滚动触发（`extentAfter < 720`），`PageStorageKey('actors-scroll')` 保持滚动位置——与 `PersonWorksPage` 同款。
- 卡片：圆形头像（`PeekMediaImage kind: person`）+ 名字；网格列数随宽度自适应（<520:2、<760:3、<1000:4、<1260:5、其余 6）。
- 点击卡片：由 `MediaItem` 构造 `MediaPerson`（id/name/type:'Actor'/imageUri/imageHeaders）→ push 现有 `PersonWorksPage`。
- `PersonWorksPage` 内点作品 → push `MediaDetailPage`（与收藏页 `_openItem` 同款）。
- 空态/错误：未登录 → 「登录后浏览演员」+ 按钮跳媒体库页（`onOpenLibrary`）；已登录无数据 → 「媒体库中暂无演员信息」；请求失败 → 错误卡片 + 重新加载（`forceRefresh`）。文案与全应用一致（中文）。

## 导航接线

`home_shell.dart`：

- `_destinations` **末尾追加**：`_AppDestination('演员', Icons.people_outline_rounded, Icons.people_rounded)`，顺序变为 首页/媒体库/收藏/搜索/演员/设置。
- 追加而非插入，保证 Ctrl+1~5 不变；`CallbackShortcuts` 新增 `digit6` → `_selectDestination(5)`。
- PageView 页面构建加 `ActorsPage(key: _actorsPageKey, account: _authenticatedServer, onOpenLibrary: ...)`，按需创建/保活机制照旧。
- 实测窄窗口 NavigationBar 6 项布局是否溢出（720px 以下每项约 120px，Material 支持 6 项）。

## 文档同步

- `README.md`：快捷键表加 `Ctrl+6`、功能概览表加「演员」行、项目结构加 `people/`。
- `docs/ARCHITECTURE.md`：导航段落「小屏使用五项底部导航」改六项；补一句人物浏览说明。
- `CLAUDE.md`：导航 5 项 → 6 项。

## 测试

- `media_library_service_test.dart`：`getActors` 的 URL 参数（`PersonTypes=Actor`/`Recursive`/分页）、解析（头像 URI、总记录数）、缓存行为。
- 新 `actors_page_test.dart`（仿 `favorites_page_test`）：未登录空态、网格渲染、空库、错误重试、点击卡片进入 `PersonWorksPage`。
- `home_shell_interaction_test.dart`：Ctrl+6 切换 + 页面保活。
- 不涉及 `PlaybackRuntime` 与原生层。
