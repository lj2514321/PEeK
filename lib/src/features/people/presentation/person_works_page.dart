import 'dart:async';

import 'package:embyplayer/src/app/app_chrome.dart';
import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/domain/media_item.dart';
import 'package:embyplayer/src/core/domain/server.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_3d_card.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/people/domain/actor_favorite.dart';
import 'package:embyplayer/src/features/people/presentation/actor_favorites_provider.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PersonWorksPage extends ConsumerStatefulWidget {
  const PersonWorksPage({
    super.key,
    required this.account,
    required this.person,
    required this.onOpen,
  });

  final AuthenticatedServer account;
  final MediaPerson person;
  final ValueChanged<MediaItem> onOpen;

  @override
  ConsumerState<PersonWorksPage> createState() => _PersonWorksPageState();
}

class _PersonWorksPageState extends ConsumerState<PersonWorksPage> {
  static const _pageSize = 40;

  final _scrollController = SmoothScrollController();
  List<MediaItem> _items = const [];
  int _totalItemCount = 0;
  int _nextStartIndex = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _paginationError;

  bool get _hasMore =>
      _items.isNotEmpty &&
      _items.length < _totalItemCount &&
      _nextStartIndex > 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    Future<void>.microtask(_loadInitial);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        !_hasMore ||
        _loadingMore ||
        _paginationError != null) {
      return;
    }
    if (_scrollController.position.extentAfter < 720) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadInitial({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _paginationError = null;
    });
    try {
      final page = await ref
          .read(mediaLibraryProvider)
          .getItemsForPerson(
            widget.account,
            personId: widget.person.id,
            limit: _pageSize,
            forceRefresh: forceRefresh,
          );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _totalItemCount = page.totalRecordCount;
        _nextStartIndex = page.nextStartIndex;
      });
    } on MediaLibraryException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _paginationError = null;
    });
    try {
      final page = await ref
          .read(mediaLibraryProvider)
          .getItemsForPerson(
            widget.account,
            personId: widget.person.id,
            startIndex: _nextStartIndex,
            limit: _pageSize,
          );
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _paginationError = error.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final favorite = ActorFavorite.fromMediaPerson(widget.person);
    final isNowFav =
        await ref.read(actorFavoritesProvider.notifier).toggleFavorite(favorite);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isNowFav
              ? '已将 ${widget.person.name} 加入演员收藏'
              : '已从收藏中移除 ${widget.person.name}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFav = ref
        .watch(actorFavoritesProvider)
        .maybeWhen(
          data: (_) =>
              ref.read(actorFavoritesProvider.notifier).isFavorite(widget.person.id),
          orElse: () => false,
        );

    return Scaffold(
      body: AmbientBackdrop(
        child: PeekSmoothScroll(
          controller: _scrollController,
          child: CustomScrollView(
            key: const PageStorageKey('person-works-scroll'),
            controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              backgroundColor: AppColors.canvas.withValues(alpha: 0.85),
              leading: IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                widget.person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              actions: [
                IconButton(
                  key: const ValueKey('actor-favorite-button'),
                  tooltip: isFav ? '已收藏演员' : '收藏演员',
                  icon: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 20,
                    color: isFav ? const Color(0xFFFF4081) : Colors.white70,
                  ),
                  onPressed: _toggleFavorite,
                ),
                if (defaultTargetPlatform == TargetPlatform.windows)
                  const SizedBox(width: AppChrome.windowControlsWidth),
              ],
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                    child: _PersonWorksHeader(
                      person: widget.person,
                      total: _totalItemCount,
                      loading: _loading,
                      isFavorite: isFav,
                      onToggleFavorite: _toggleFavorite,
                    ),
                  ),
                ),
              ),
            ),
            if (_loading && _items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _PersonWorksMessage(
                  icon: Icons.cloud_off_rounded,
                  title: '暂时无法读取作品',
                  message: _error!,
                  actionLabel: '重新加载',
                  onAction: () => _loadInitial(forceRefresh: true),
                ),
              )
            else if (_items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _PersonWorksMessage(
                  icon: Icons.movie_filter_outlined,
                  title: '媒体库中暂无相关作品',
                  message: '服务器没有返回这位演员参演的电影、剧集或视频。',
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
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 22,
                        childAspectRatio: 0.62,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _PersonWorkCard(
                          item: item,
                          onOpen: () => widget.onOpen(item),
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
      ),
    );
  }
}

class _PersonWorksHeader extends StatelessWidget {
  const _PersonWorksHeader({
    required this.person,
    required this.total,
    required this.loading,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final MediaPerson person;
  final int total;
  final bool loading;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: AppGlass.decoration(radius: 20, selected: true),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: PeekMediaImage(
                uri: person.imageUri,
                headers: person.imageHeaders,
                kind: PeekMediaImageKind.person,
                placeholderBackground: AppColors.surfaceHigh,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onToggleFavorite,
                      icon: Icon(
                        isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 16,
                        color: isFavorite ? const Color(0xFFFF4081) : null,
                      ),
                      label: Text(isFavorite ? '已收藏' : '收藏演员'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  loading ? '正在整理媒体库作品…' : '媒体库中共 $total 部相关作品',
                  style: const TextStyle(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonWorkCard extends StatelessWidget {
  const _PersonWorkCard({required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '查看 ${item.name} 详情',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Peek3DCard(
              onTap: onOpen,
              borderRadius: 15,
              child: Material(
                color: AppColors.surfaceLow,
                borderRadius: BorderRadius.circular(15),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('person-work-${item.id}'),
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
                      if (item.played)
                        const Positioned(
                          top: 10,
                          right: 10,
                          child: _PlayedBadge(),
                        ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.76),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('查看详情', style: TextStyle(fontSize: 10)),
                              SizedBox(width: 3),
                              Icon(Icons.arrow_forward_rounded, size: 13),
                            ],
                          ),
                        ),
                      ),
                    ],
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
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            _metadata(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PlayedBadge extends StatelessWidget {
  const _PlayedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: AppColors.success,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, color: AppColors.canvas, size: 18),
    );
  }
}

class _PersonWorksMessage extends StatelessWidget {
  const _PersonWorksMessage({
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
    MediaItemKind.person => '演员',
    MediaItemKind.folder => '文件夹',
  };
}

IconData _kindIcon(MediaItemKind kind) {
  return switch (kind) {
    MediaItemKind.movie => Icons.movie_outlined,
    MediaItemKind.series => Icons.live_tv_outlined,
    MediaItemKind.season => Icons.video_library_outlined,
    MediaItemKind.episode => Icons.play_circle_outline_rounded,
    MediaItemKind.video => Icons.ondemand_video_rounded,
    MediaItemKind.audio => Icons.music_note_rounded,
    MediaItemKind.person => Icons.person_outline_rounded,
    MediaItemKind.folder => Icons.folder_outlined,
  };
}
