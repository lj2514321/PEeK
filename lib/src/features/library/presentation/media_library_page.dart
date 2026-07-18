import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MediaLibraryPage extends ConsumerStatefulWidget {
  const MediaLibraryPage({
    super.key,
    required this.account,
    required this.onGoHome,
    this.onSessionExpired,
  });

  final AuthenticatedServer? account;
  final VoidCallback onGoHome;
  final VoidCallback? onSessionExpired;

  @override
  ConsumerState<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends ConsumerState<MediaLibraryPage> {
  static const _pageSize = 60;

  final _scrollController = ScrollController();
  List<MediaItem> _libraries = const [];
  List<MediaItem> _items = const [];
  List<MediaItem> _path = const [];
  MediaItem? _selectedLibrary;
  int _totalItemCount = 0;
  int _nextStartIndex = 0;
  bool _loadingCatalog = false;
  bool _loadingItems = false;
  bool _loadingMore = false;
  String? _error;
  String? _paginationError;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearEnd);
    if (widget.account != null) Future<void>.microtask(_loadCatalog);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MediaLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.account;
    final current = widget.account;
    if (previous?.userId != current?.userId ||
        previous?.server.serverId != current?.server.serverId) {
      if (current == null) {
        _requestGeneration++;
        setState(() {
          _libraries = const [];
          _items = const [];
          _path = const [];
          _selectedLibrary = null;
          _totalItemCount = 0;
          _nextStartIndex = 0;
          _error = null;
          _paginationError = null;
        });
      } else {
        _loadCatalog();
      }
    }
  }

  Future<void> _loadCatalog({bool forceRefresh = false}) async {
    final account = widget.account;
    if (account == null) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loadingCatalog = true;
      _loadingItems = false;
      _loadingMore = false;
      _error = null;
      _paginationError = null;
    });

    try {
      final service = ref.read(mediaLibraryProvider);
      final libraries = await service.getLibraries(
        account,
        forceRefresh: forceRefresh,
      );
      final selected = libraries.isEmpty ? null : libraries.first;
      final page = selected == null
          ? null
          : await service.getItems(
              account,
              parentId: selected.id,
              limit: _pageSize,
              forceRefresh: forceRefresh,
            );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _libraries = libraries;
        _selectedLibrary = selected;
        _path = selected == null ? const [] : [selected];
        _items = page?.items ?? const [];
        _totalItemCount = page?.totalRecordCount ?? 0;
        _nextStartIndex = page?.nextStartIndex ?? 0;
      });
    } on MediaLibraryException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      setState(() => _error = error.message);
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingCatalog = false);
      }
    }
  }

  Future<void> _selectLibrary(MediaItem library) async {
    if (library.id == _selectedLibrary?.id && _path.length == 1) return;
    setState(() => _selectedLibrary = library);
    await _loadNode(library, path: [library]);
  }

  Future<void> _openItem(MediaItem item) async {
    if (_isBrowsable(item)) {
      await _loadNode(item, path: [..._path, item]);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            MediaDetailPage(account: widget.account!, initialItem: item),
      ),
    );
    if (mounted) await _reloadCurrentNode();
  }

  Future<void> _navigateTo(int index) async {
    if (index < 0 || index >= _path.length || index == _path.length - 1) {
      return;
    }
    final nextPath = _path.sublist(0, index + 1);
    await _loadNode(nextPath.last, path: nextPath);
  }

  Future<void> _loadNode(
    MediaItem node, {
    required List<MediaItem> path,
    bool forceRefresh = false,
  }) async {
    final account = widget.account;
    if (account == null) return;
    final generation = ++_requestGeneration;
    setState(() {
      _path = path;
      _items = const [];
      _totalItemCount = 0;
      _nextStartIndex = 0;
      _loadingItems = true;
      _loadingMore = false;
      _error = null;
      _paginationError = null;
    });

    try {
      final page = await ref
          .read(mediaLibraryProvider)
          .getItems(
            account,
            parentId: node.id,
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
      setState(() => _error = error.message);
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingItems = false);
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
        _path.isEmpty ||
        _loadingCatalog ||
        _loadingItems ||
        _loadingMore ||
        _nextStartIndex >= _totalItemCount) {
      return;
    }
    final generation = _requestGeneration;
    final node = _path.last;
    setState(() {
      _loadingMore = true;
      _paginationError = null;
    });

    try {
      final page = await ref
          .read(mediaLibraryProvider)
          .getItems(
            account,
            parentId: node.id,
            startIndex: _nextStartIndex,
            limit: _pageSize,
          );
      if (!mounted || generation != _requestGeneration) return;
      final existingIds = _items.map((item) => item.id).toSet();
      setState(() {
        _items = [
          ..._items,
          ...page.items.where((item) => existingIds.add(item.id)),
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

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    if (account == null) {
      return _LibraryMessage(
        icon: Icons.lock_outline_rounded,
        title: '登录后读取媒体库',
        message: '先连接并登录 Jellyfin 或 Emby，媒体库内容才会显示在这里。',
        actionLabel: '返回首页连接',
        onAction: widget.onGoHome,
      );
    }

    if (_loadingCatalog && _libraries.isEmpty) {
      return const _LoadingLibrary();
    }

    if (_error != null && _libraries.isEmpty) {
      return _LibraryMessage(
        icon: Icons.cloud_off_rounded,
        title: '媒体库读取失败',
        message: _error!,
        actionLabel: '重新加载',
        onAction: _loadCatalog,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 720 ? 20.0 : 32.0;
        return RefreshIndicator(
          onRefresh: () => _loadCatalog(forceRefresh: true),
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              28,
              horizontalPadding,
              48,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LibraryHeader(
                      account: account,
                      onRefresh: () => _loadCatalog(forceRefresh: true),
                    ),
                    const SizedBox(height: 28),
                    if (_libraries.isEmpty)
                      _LibraryMessage(
                        icon: Icons.video_library_outlined,
                        title: '服务器没有可见媒体库',
                        message: '请检查当前用户的媒体库访问权限，然后重新加载。',
                        actionLabel: '重新加载',
                        onAction: _loadCatalog,
                        embedded: true,
                      )
                    else ...[
                      _SectionLabel(
                        eyebrow: 'COLLECTIONS',
                        title: '我的媒体库',
                        detail: '${_libraries.length} 个可访问媒体库',
                      ),
                      const SizedBox(height: 14),
                      _LibrarySelector(
                        libraries: _libraries,
                        selectedId: _selectedLibrary?.id,
                        onSelected: _selectLibrary,
                      ),
                      const SizedBox(height: 32),
                      if (_path.isNotEmpty) ...[
                        _LibraryBreadcrumb(
                          path: _path,
                          onSelected: _navigateTo,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _SectionLabel(
                        eyebrow: 'BROWSE',
                        title: _path.isEmpty ? '媒体内容' : _path.last.name,
                        detail: _loadingItems
                            ? '正在同步'
                            : '已加载 ${_items.length} / $_totalItemCount 项',
                      ),
                      const SizedBox(height: 16),
                      if (_error != null)
                        _InlineLibraryError(
                          message: _error!,
                          onRetry: _path.isEmpty
                              ? _loadCatalog
                              : () => _reloadCurrentNode(),
                        )
                      else if (_loadingItems)
                        const _ItemsLoadingGrid()
                      else if (_items.isEmpty)
                        const _EmptyLibrary()
                      else ...[
                        _MediaGrid(items: _items, onOpen: _openItem),
                        _PaginationFooter(
                          loadedCount: _items.length,
                          totalCount: _totalItemCount,
                          hasMore: _nextStartIndex < _totalItemCount,
                          loading: _loadingMore,
                          error: _paginationError,
                          onLoadMore: _loadMore,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _reloadCurrentNode() async {
    if (_path.isEmpty) return _loadCatalog(forceRefresh: true);
    await _loadNode(_path.last, path: _path, forceRefresh: true);
  }

  bool _isBrowsable(MediaItem item) {
    return item.kind == MediaItemKind.folder ||
        item.kind == MediaItemKind.series ||
        item.kind == MediaItemKind.season;
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.account, required this.onRefresh});

  final AuthenticatedServer account;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MEDIA SHELVES',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '晚上好，${account.userName}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '正在浏览 ${account.server.name} · ${account.server.kind.label} ${account.server.version}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: '刷新媒体库',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.eyebrow,
    required this.title,
    required this.detail,
  });

  final String eyebrow;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 6),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
        Text(
          detail,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
      ],
    );
  }
}

class _LibraryBreadcrumb extends StatelessWidget {
  const _LibraryBreadcrumb({required this.path, required this.onSelected});

  final List<MediaItem> path;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var index = 0; index < path.length; index++) ...[
          if (index > 0)
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
          TextButton(
            onPressed: index == path.length - 1
                ? null
                : () => onSelected(index),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(path[index].name),
          ),
        ],
      ],
    );
  }
}

class _LibrarySelector extends StatelessWidget {
  const _LibrarySelector({
    required this.libraries,
    required this.selectedId,
    required this.onSelected,
  });

  final List<MediaItem> libraries;
  final String? selectedId;
  final ValueChanged<MediaItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 460
            ? constraints.maxWidth
            : constraints.maxWidth < 720
            ? (constraints.maxWidth - 12) / 2
            : 210.0;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final library in libraries)
              _LibraryChoice(
                library: library,
                selected: library.id == selectedId,
                width: cardWidth,
                onSelected: onSelected,
              ),
          ],
        );
      },
    );
  }
}

class _LibraryChoice extends StatelessWidget {
  const _LibraryChoice({
    required this.library,
    required this.selected,
    required this.width,
    required this.onSelected,
  });

  final MediaItem library;
  final bool selected;
  final double width;
  final ValueChanged<MediaItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: () => onSelected(library),
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            width: width,
            height: 86,
            padding: const EdgeInsets.all(14),
            decoration: AppGlass.decoration(radius: 15, selected: selected),
            child: Row(
              children: [
                _LibraryIcon(item: library, selected: selected),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        library.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selected ? '正在浏览' : '打开媒体库',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryIcon extends StatelessWidget {
  const _LibraryIcon({required this.item, required this.selected});

  final MediaItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.spotlight.withValues(alpha: 0.12)
            : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: item.imageUri == null
          ? Icon(
              Icons.video_library_rounded,
              color: selected ? AppColors.spotlight : AppColors.textTertiary,
            )
          : Image.network(
              item.imageUri.toString(),
              headers: item.imageHeaders,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.video_library_rounded,
                color: AppColors.textTertiary,
              ),
            ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.items, required this.onOpen});

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          < 520 => 2,
          < 780 => 3,
          < 1040 => 4,
          < 1240 => 5,
          _ => 6,
        };
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 20,
            childAspectRatio: 0.62,
          ),
          itemBuilder: (context, index) => _MediaCard(
            item: items[index],
            onOpen: () => onOpen(items[index]),
          ),
        );
      },
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = item.runTime == null || item.runTime == Duration.zero
        ? 0.0
        : (item.resumePosition.inMilliseconds / item.runTime!.inMilliseconds)
              .clamp(0.0, 1.0);
    final browsable =
        item.kind == MediaItemKind.folder ||
        item.kind == MediaItemKind.series ||
        item.kind == MediaItemKind.season;
    return Semantics(
      label: '${item.name}，${_kindLabel(item.kind)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Material(
              color: AppColors.surfaceLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpen,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _MediaArtwork(item: item),
                    if (item.played)
                      const Positioned(
                        top: 10,
                        right: 10,
                        child: _PlayedBadge(),
                      ),
                    if (browsable)
                      const Positioned(
                        left: 10,
                        bottom: 10,
                        child: _BrowseBadge(),
                      ),
                    if (progress > 0 && progress < 1)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
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

  String _metadata(MediaItem item) {
    final parts = <String>[_kindLabel(item.kind)];
    if (item.productionYear != null) parts.add('${item.productionYear}');
    if (item.runTime != null && item.runTime!.inMinutes > 0) {
      parts.add('${item.runTime!.inMinutes} 分钟');
    }
    return parts.join(' · ');
  }
}

class _BrowseBadge extends StatelessWidget {
  const _BrowseBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('进入', style: TextStyle(fontSize: 10)),
          SizedBox(width: 3),
          Icon(Icons.arrow_forward_rounded, size: 13),
        ],
      ),
    );
  }
}

class _MediaArtwork extends StatelessWidget {
  const _MediaArtwork({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceHigh, AppColors.surfaceLow],
        ),
      ),
      child: Center(
        child: Icon(
          _kindIcon(item.kind),
          color: AppColors.textTertiary,
          size: 38,
        ),
      ),
    );
    final imageUri = item.imageUri;
    if (imageUri == null) return placeholder;
    return Image.network(
      imageUri.toString(),
      headers: item.imageHeaders,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => placeholder,
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

class _InlineLibraryError extends StatelessWidget {
  const _InlineLibraryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.12),
            blurRadius: 20,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.loadedCount,
    required this.totalCount,
    required this.hasMore,
    required this.loading,
    required this.error,
    required this.onLoadMore,
  });

  final int loadedCount;
  final int totalCount;
  final bool hasMore;
  final bool loading;
  final String? error;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Center(
        child: AnimatedSwitcher(
          duration: AppMotion.fast,
          child: loading
              ? const Row(
                  key: ValueKey('loading-more'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('正在加载更多…'),
                  ],
                )
              : error != null
              ? Row(
                  key: const ValueKey('load-more-error'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(onPressed: onLoadMore, child: const Text('重试')),
                  ],
                )
              : hasMore
              ? OutlinedButton.icon(
                  key: const ValueKey('load-more'),
                  onPressed: onLoadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text('加载更多（$loadedCount / $totalCount）'),
                )
              : Container(
                  key: const ValueKey('all-loaded'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '已加载全部 $loadedCount 项',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _LoadingLibrary extends StatelessWidget {
  const _LoadingLibrary();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text('正在从服务器读取媒体库…'),
        ],
      ),
    );
  }
}

class _ItemsLoadingGrid extends StatelessWidget {
  const _ItemsLoadingGrid();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 220,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 34, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text('这个媒体库暂时没有可显示的内容'),
        ],
      ),
    );
  }
}

class _LibraryMessage extends StatelessWidget {
  const _LibraryMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.embedded = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: 540,
      padding: const EdgeInsets.all(36),
      decoration: AppGlass.decoration(radius: 20, elevated: true),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppColors.spotlight),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
    if (embedded) return Center(child: content);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: content,
      ),
    );
  }
}

String _kindLabel(MediaItemKind kind) {
  return switch (kind) {
    MediaItemKind.movie => '电影',
    MediaItemKind.series => '剧集',
    MediaItemKind.season => '季',
    MediaItemKind.episode => '单集',
    MediaItemKind.video => '视频',
    MediaItemKind.audio => '音乐',
    MediaItemKind.folder => '文件夹',
  };
}

IconData _kindIcon(MediaItemKind kind) {
  return switch (kind) {
    MediaItemKind.movie => Icons.movie_outlined,
    MediaItemKind.series => Icons.live_tv_outlined,
    MediaItemKind.season => Icons.video_collection_outlined,
    MediaItemKind.episode => Icons.play_circle_outline_rounded,
    MediaItemKind.video => Icons.videocam_outlined,
    MediaItemKind.audio => Icons.album_outlined,
    MediaItemKind.folder => Icons.folder_outlined,
  };
}
