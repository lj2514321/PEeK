import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_3d_card.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/app/app_routes.dart';
import 'package:embyplayer/src/features/people/domain/actor_favorite.dart';
import 'package:embyplayer/src/features/people/presentation/actor_favorites_provider.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({
    super.key,
    required this.account,
    required this.onGoHome,
    required this.onOpenLibrary,
    this.onSessionExpired,
  });

  final AuthenticatedServer? account;
  final VoidCallback onGoHome;
  final VoidCallback onOpenLibrary;
  final VoidCallback? onSessionExpired;

  @override
  ConsumerState<FavoritesPage> createState() => FavoritesPageState();
}

class FavoritesPageState extends ConsumerState<FavoritesPage> {
  static const _pageSize = 60;

  final _scrollController = SmoothScrollController();
  List<MediaItem> _items = const [];
  Set<String> _updatingIds = {};
  int _totalItemCount = 0;
  int _nextStartIndex = 0;
  int _requestGeneration = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _paginationError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearEnd);
    if (widget.account != null) {
      Future<void>.microtask(_loadFavorites);
    }
  }

  @override
  void didUpdateWidget(covariant FavoritesPage oldWidget) {
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
          _updatingIds = {};
        });
      } else {
        _loadFavorites();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> refresh() => _loadFavorites(forceRefresh: true);

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

  Future<void> _loadFavorites({bool forceRefresh = false}) async {
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
          .getFavoriteItems(
            account,
            limit: _pageSize,
            forceRefresh: forceRefresh,
          );
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
        ).showSnackBar(SnackBar(content: Text('刷新收藏失败：${error.message}')));
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
          .getFavoriteItems(
            account,
            startIndex: _nextStartIndex,
            limit: _pageSize,
          );
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

  Future<void> _openItem(MediaItem item) async {
    final account = widget.account;
    if (account == null) return;
    final currentScrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : null;
    final updatedItem = await AppRoutes.openMediaDetail(
      context,
      account: account,
      item: item,
    );
    if (!mounted) return;
    if (updatedItem != null) {
      if (!updatedItem.favorite) {
        setState(() {
          _items = _items
              .where((candidate) => candidate.id != updatedItem.id)
              .toList(growable: false);
          _totalItemCount = _totalItemCount > 0 ? _totalItemCount - 1 : 0;
          _nextStartIndex = _nextStartIndex > 0 ? _nextStartIndex - 1 : 0;
        });
      } else {
        final index = _items.indexWhere((it) => it.id == updatedItem.id);
        if (index != -1) {
          setState(() {
            final next = List<MediaItem>.from(_items);
            next[index] = updatedItem;
            _items = next;
          });
        }
      }
    }
    if (currentScrollOffset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final maxScroll = _scrollController.position.maxScrollExtent;
        final clamped = currentScrollOffset.clamp(0.0, maxScroll);
        if ((_scrollController.offset - clamped).abs() > 1.0) {
          _scrollController.jumpTo(clamped);
        }
      });
    }
  }

  Future<void> _removeFavorite(MediaItem item) async {
    final account = widget.account;
    if (account == null || _updatingIds.contains(item.id)) return;
    setState(() => _updatingIds = {..._updatingIds, item.id});
    try {
      await ref
          .read(mediaLibraryProvider)
          .setFavorite(account, item.id, favorite: false);
      if (!mounted) return;
      setState(() {
        _items = _items
            .where((candidate) => candidate.id != item.id)
            .toList(growable: false);
        _totalItemCount = _totalItemCount > 0 ? _totalItemCount - 1 : 0;
        _nextStartIndex = _nextStartIndex > 0 ? _nextStartIndex - 1 : 0;
      });
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 2500),
            content: Text('已从收藏移除《${item.name}》'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => _restoreFavorite(item),
            ),
          ),
        );
    } on MediaLibraryException catch (error) {
      if (!mounted) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('取消收藏失败：${error.message}')));
    } finally {
      if (mounted) {
        setState(() {
          final next = {..._updatingIds}..remove(item.id);
          _updatingIds = next;
        });
      }
    }
  }

  Future<void> _restoreFavorite(MediaItem item) async {
    final account = widget.account;
    if (account == null) return;
    try {
      await ref
          .read(mediaLibraryProvider)
          .setFavorite(account, item.id, favorite: true);
      if (!mounted) return;
      await _loadFavorites(forceRefresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已恢复收藏')));
    } on MediaLibraryException catch (error) {
      if (!mounted) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('恢复收藏失败：${error.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    if (account == null) {
      return _FavoritesMessage(
        icon: Icons.lock_outline_rounded,
        title: '登录后查看收藏',
        message: '连接并登录 Jellyfin 或 Emby 后，你收藏的影片和剧集会集中显示在这里。',
        actionLabel: '返回首页连接',
        onAction: widget.onGoHome,
      );
    }

    if (_loading && _items.isEmpty) {
      return const _FavoritesLoading();
    }

    if (_error != null && _items.isEmpty) {
      return _FavoritesMessage(
        icon: Icons.cloud_off_rounded,
        title: '收藏读取失败',
        message: _error!,
        actionLabel: '重新加载',
        onAction: _loadFavorites,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 720 ? 20.0 : 32.0;
        return RefreshIndicator(
          onRefresh: refresh,
          child: PeekSmoothScroll(
            controller: _scrollController,
            child: CustomScrollView(
              key: const PageStorageKey('favorites-scroll-view'),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    20,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
                        child: _FavoritesHeader(
                          account: account,
                          count: _totalItemCount,
                          loading: _loading,
                          onRefresh: refresh,
                        ),
                      ),
                    ),
                  ),
                ),
                if (ref.watch(actorFavoritesProvider).value?.isNotEmpty ??
                    false)
                  SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            0,
                            horizontalPadding,
                            24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '收藏的演员 (${(ref.watch(actorFavoritesProvider).value ?? []).length})',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 110,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount:
                                      (ref
                                                  .watch(actorFavoritesProvider)
                                                  .value ??
                                              [])
                                          .length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(width: 14),
                                  itemBuilder: (context, index) {
                                    final actor =
                                        (ref
                                            .watch(actorFavoritesProvider)
                                            .value ??
                                        [])[index];
                                    return _FavoriteActorChipCard(
                                      actor: actor,
                                      onTap: () {
                                        AppRoutes.openPersonWorks(
                                          context,
                                          account: account,
                                          person: actor.toMediaPerson(),
                                          onOpen: (item) => _openItem(item),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _FavoritesMessage(
                      icon: Icons.favorite_border_rounded,
                      title: '收藏还是空的',
                      message: '在详情页点亮心形图标，喜欢的电影、剧集和单集就会出现在这里。',
                      actionLabel: '去媒体库看看',
                      onAction: widget.onOpenLibrary,
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      0,
                      horizontalPadding,
                      48,
                    ),
                    sliver: SliverLayoutBuilder(
                      builder: (context, gridConstraints) {
                        final width = gridConstraints.crossAxisExtent.clamp(
                          0.0,
                          1280.0,
                        );
                        final columns = switch (width) {
                          < 520 => 2,
                          < 780 => 3,
                          < 1040 => 4,
                          < 1240 => 5,
                          _ => 6,
                        };
                        return SliverGrid(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final item = _items[index];
                            return PeekStaggeredGridItem(
                              key: ValueKey(
                                'fav-stagger-$_requestGeneration-$index-${item.id}',
                              ),
                              index: index,
                              columns: columns,
                              child: _FavoriteMediaCard(
                                item: item,
                                updating: _updatingIds.contains(item.id),
                                onOpen: () => _openItem(item),
                                onRemove: () => _removeFavorite(item),
                              ),
                            );
                          }, childCount: _items.length),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 20,
                                childAspectRatio: 0.62,
                              ),
                        );
                      },
                    ),
                  ),
                if (_loadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 28),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                if (_paginationError != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        28,
                      ),
                      child: _FavoritesPaginationError(
                        message: _paginationError!,
                        onRetry: _loadMore,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FavoritesHeader extends StatelessWidget {
  const _FavoritesHeader({
    required this.account,
    required this.count,
    required this.loading,
    required this.onRefresh,
  });

  final AuthenticatedServer account;
  final int count;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.spotlight.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.favorite_rounded,
            color: AppColors.spotlight,
            size: 27,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR COLLECTION',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 7),
              Text('我的收藏', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 5),
              Text(
                '$count 项内容 · ${account.server.name}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: '刷新收藏',
          onPressed: loading ? null : onRefresh,
          icon: loading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _FavoriteMediaCard extends StatelessWidget {
  const _FavoriteMediaCard({
    required this.item,
    required this.updating,
    required this.onOpen,
    required this.onRemove,
  });

  final MediaItem item;
  final bool updating;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final progress = item.runTime == null || item.runTime == Duration.zero
        ? 0.0
        : (item.resumePosition.inMilliseconds / item.runTime!.inMilliseconds)
              .clamp(0.0, 1.0);
    return Semantics(
      button: true,
      label: '查看 ${item.name} 详情',
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: AppGlass.decoration(radius: AppRadius.value),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Peek3DCard(
                onTap: onOpen,
                borderRadius: AppRadius.value,
                child: Material(
                  key: ValueKey('favorite-card-${item.id}'),
                  color: AppColors.surfaceLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.borderRadius,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.20),
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onOpen,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PeekMediaImage(
                          uri: item.imageUri,
                          headers: item.imageHeaders,
                          kind: PeekMediaImageKind.poster,
                          fit: BoxFit.cover,
                          placeholderIcon: _kindIcon(item.kind),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Tooltip(
                            message: '从收藏移除',
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.56),
                              shape: AppRadius.shape,
                              child: IconButton(
                                key: ValueKey('remove-favorite-${item.id}'),
                                onPressed: updating ? null : onRemove,
                                icon: updating
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.favorite_rounded,
                                        color: Color(0xFFFF6B8A),
                                        size: 20,
                                      ),
                              ),
                            ),
                          ),
                        ),
                        if (item.played)
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: AppColors.success,
                                borderRadius: AppRadius.borderRadius,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: AppColors.canvas,
                                size: 18,
                              ),
                            ),
                          ),
                        if (progress > 0 && progress < 1)
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: ClipRRect(
                              borderRadius: AppRadius.borderRadius,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor: Colors.black54,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                _metadata(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesLoading extends StatelessWidget {
  const _FavoritesLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text('正在整理你的收藏…'),
        ],
      ),
    );
  }
}

class _FavoritesMessage extends StatelessWidget {
  const _FavoritesMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: GlassSurface(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 42, color: AppColors.spotlight),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoritesPaginationError extends StatelessWidget {
  const _FavoritesPaginationError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(
            '加载更多失败：$message',
            style: const TextStyle(color: AppColors.error),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

String _metadata(MediaItem item) {
  final parts = <String>[_kindLabel(item.kind)];
  if (item.productionYear != null) parts.add('${item.productionYear}');
  if (item.runTime != null && item.runTime!.inMinutes > 0) {
    parts.add('${item.runTime!.inMinutes} 分钟');
  }
  return parts.join(' · ');
}

String _kindLabel(MediaItemKind kind) {
  return switch (kind) {
    MediaItemKind.movie => '电影',
    MediaItemKind.series => '剧集',
    MediaItemKind.season => '季',
    MediaItemKind.episode => '单集',
    MediaItemKind.video => '视频',
    MediaItemKind.audio => '音频',
    MediaItemKind.person => '人物',
    MediaItemKind.folder => '文件夹',
  };
}

IconData _kindIcon(MediaItemKind kind) {
  return switch (kind) {
    MediaItemKind.movie => Icons.movie_outlined,
    MediaItemKind.series => Icons.live_tv_outlined,
    MediaItemKind.season => Icons.video_collection_outlined,
    MediaItemKind.episode => Icons.smart_display_outlined,
    MediaItemKind.video => Icons.play_circle_outline_rounded,
    MediaItemKind.audio => Icons.audiotrack_rounded,
    MediaItemKind.person => Icons.person_outline_rounded,
    MediaItemKind.folder => Icons.folder_outlined,
  };
}

class _FavoriteActorChipCard extends StatelessWidget {
  const _FavoriteActorChipCard({required this.actor, required this.onTap});

  final ActorFavorite actor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 52,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: PeekMediaImage(
                    uri: actor.imageUri,
                    headers: actor.imageHeaders,
                    kind: PeekMediaImageKind.person,
                    placeholderBackground: AppColors.surfaceHigh,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                actor.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
