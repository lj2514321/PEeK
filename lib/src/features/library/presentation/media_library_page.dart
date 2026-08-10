import 'package:cached_network_image/cached_network_image.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_3d_card.dart';
import 'package:embyplayer/src/core/presentation/peek_horizontal_rail.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/local_library/data/local_media_library_service.dart';
import 'package:embyplayer/src/features/local_library/domain/local_media_library.dart';
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
    this.localLibraries = const [],
    this.onAddLocalLibrary,
    this.onSessionExpired,
  });

  final AuthenticatedServer? account;
  final VoidCallback onGoHome;
  final List<LocalMediaLibrary> localLibraries;
  final VoidCallback? onAddLocalLibrary;
  final VoidCallback? onSessionExpired;

  @override
  ConsumerState<MediaLibraryPage> createState() => MediaLibraryPageState();
}

enum MediaGridDensity { spacious, standard, compact }

class MediaLibraryPageState extends ConsumerState<MediaLibraryPage> {
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
  String? _catalogNotice;
  int _requestGeneration = 0;
  MediaLibrarySort _sort = MediaLibrarySort.nameAscending;
  MediaLibraryKindFilter _kindFilter = MediaLibraryKindFilter.all;
  MediaLibraryStatusFilter _statusFilter = MediaLibraryStatusFilter.all;
  MediaResolutionFilter _resolutionFilter = MediaResolutionFilter.all;
  double? _minCommunityRating;
  int? _productionYear;
  MediaGridDensity _density = MediaGridDensity.standard;
  Set<String> _selectedIds = {};
  bool _selectionMode = false;
  String? _bulkActionLabel;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearEnd);
    Future<void>.microtask(_loadCatalog);
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
    final localLibrariesChanged = !_sameLocalLibraries(
      oldWidget.localLibraries,
      widget.localLibraries,
    );
    if (previous?.userId != current?.userId ||
        previous?.server.serverId != current?.server.serverId ||
        localLibrariesChanged) {
      _loadCatalog();
    }
  }

  Future<void> _loadCatalog({bool forceRefresh = false}) async {
    final account = widget.account;
    final generation = ++_requestGeneration;
    setState(() {
      _loadingCatalog = true;
      _loadingItems = false;
      _loadingMore = false;
      _error = null;
      _paginationError = null;
      _catalogNotice = null;
    });

    try {
      final localService = ref.read(localMediaLibraryProvider);
      final localLibraries = widget.localLibraries
          .map(localService.libraryItem)
          .toList(growable: false);
      var remoteLibraries = <MediaItem>[];
      String? catalogNotice;
      if (account != null) {
        try {
          remoteLibraries = await ref
              .read(mediaLibraryProvider)
              .getLibraries(account, forceRefresh: forceRefresh);
        } on MediaLibraryException catch (error) {
          if (error.authenticationExpired) widget.onSessionExpired?.call();
          if (localLibraries.isEmpty) rethrow;
          catalogNotice = '远程媒体库暂时无法读取：${error.message}';
        }
      }
      final libraries = [...localLibraries, ...remoteLibraries];
      final previousSelection = _selectedLibrary?.id;
      final selected = libraries.cast<MediaItem?>().firstWhere(
        (library) => library?.id == previousSelection,
        orElse: () => libraries.isEmpty ? null : libraries.first,
      );
      final page = selected == null
          ? null
          : await _getPage(
              selected,
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
        _catalogNotice = catalogNotice;
        _selectionMode = false;
        _selectedIds = {};
      });
    } on MediaLibraryException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      setState(() => _error = error.message);
    } on LocalMediaLibraryException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
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
        builder: (context) => MediaDetailPage(
          account: item.isLocal ? null : widget.account,
          initialItem: item,
        ),
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
      _selectionMode = false;
      _selectedIds = {};
    });

    try {
      final page = await _getPage(
        node,
        limit: _pageSize,
        forceRefresh: forceRefresh,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _items = page.items;
        _totalItemCount = page.totalRecordCount;
        _nextStartIndex = page.nextStartIndex;
      });
      _precacheUpcomingPosters(page.items);
    } on MediaLibraryException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      setState(() => _error = error.message);
    } on LocalMediaLibraryException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingItems = false);
      }
    }
  }

  void _precacheUpcomingPosters(List<MediaItem> items) {
    if (!mounted) return;
    for (final item in items.take(24)) {
      final uri = item.imageUri;
      if (uri != null && uri.scheme != 'file') {
        precacheImage(
          CachedNetworkImageProvider(
            uri.toString(),
            headers: item.imageHeaders,
            cacheManager: PeekMediaImageCache.instance,
            cacheKey: PeekMediaImageCache.keyFor(uri),
          ),
          context,
        ).catchError((_) {});
      }
    }
  }

  void _loadMoreNearEnd() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 700) {
      _loadMore();
    }
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

  Future<void> _loadMore() async {
    if (_path.isEmpty ||
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
      final page = await _getPage(
        node,
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
      _precacheUpcomingPosters(page.items);
    } on MediaLibraryException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      setState(() => _paginationError = error.message);
    } on LocalMediaLibraryException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _paginationError = error.message);
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<MediaPage> _getPage(
    MediaItem node, {
    int startIndex = 0,
    int limit = _pageSize,
    bool forceRefresh = false,
  }) {
    if (node.isLocal) {
      return ref
          .read(localMediaLibraryProvider)
          .getItems(
            node,
            startIndex: startIndex,
            limit: limit,
            sort: _sort,
            kind: _kindFilter,
            status: _statusFilter,
            productionYear: _productionYear,
          );
    }
    final account = widget.account;
    if (account == null) {
      throw const MediaLibraryException('请先登录对应的媒体服务器。');
    }
    return ref
        .read(mediaLibraryProvider)
        .getItems(
          account,
          parentId: node.id,
          startIndex: startIndex,
          limit: limit,
          sort: _sort,
          kind: _kindFilter,
          status: _statusFilter,
          resolution: _resolutionFilter,
          minCommunityRating: _minCommunityRating,
          productionYear: _productionYear,
          forceRefresh: forceRefresh,
        );
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;

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
        final selectedItems = _items
            .where((item) => _selectedIds.contains(item.id))
            .toList(growable: false);
        final favoriteTarget =
            selectedItems.isEmpty ||
            !selectedItems.every((item) => item.favorite);
        final playedTarget =
            selectedItems.isEmpty ||
            !selectedItems.every((item) => item.played);
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
                      localLibraryCount: widget.localLibraries.length,
                      onRefresh: () => _loadCatalog(forceRefresh: true),
                    ),
                    const SizedBox(height: 28),
                    if (_catalogNotice != null) ...[
                      _InlineLibraryError(
                        message: _catalogNotice!,
                        onRetry: () => _loadCatalog(forceRefresh: true),
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_libraries.isEmpty)
                      _LibraryMessage(
                        icon: Icons.create_new_folder_outlined,
                        title: account == null ? '还没有媒体库' : '没有可见媒体库',
                        message: account == null
                            ? '添加电脑或局域网共享文件夹，也可以返回首页连接 Jellyfin / Emby。'
                            : '添加本地文件夹，或检查当前用户的服务器媒体库权限。',
                        actionLabel: '添加本地媒体库',
                        onAction: widget.onAddLocalLibrary,
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
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: AppMotion.fast,
                        child: _selectionMode
                            ? _BulkActionBar(
                                key: const ValueKey('bulk-action-bar'),
                                selectedCount: selectedItems.length,
                                allLoadedSelected:
                                    _items.isNotEmpty &&
                                    selectedItems.length == _items.length,
                                busyLabel: _bulkActionLabel,
                                favoriteTarget: favoriteTarget,
                                playedTarget: playedTarget,
                                onSelectAll: _selectAllLoaded,
                                onFavorite: () =>
                                    _applyBulkState(favorite: favoriteTarget),
                                onPlayed: () =>
                                    _applyBulkState(played: playedTarget),
                                onClose: _exitSelectionMode,
                              )
                            : _LibraryToolbar(
                                key: const ValueKey('library-toolbar'),
                                sort: _sort,
                                density: _density,
                                activeFilterCount: _activeFilterCount,
                                onSortChanged: _changeSort,
                                onFilterPressed: _showFilters,
                                onDensityChanged: _setDensity,
                                onSelectPressed:
                                    _selectedLibrary?.isLocal == true
                                    ? null
                                    : _enterSelectionMode,
                              ),
                      ),
                      const SizedBox(height: 18),
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
                        _EmptyLibrary(
                          filtered: _activeFilterCount > 0,
                          onClearFilters: _activeFilterCount > 0
                              ? () async {
                                  setState(() {
                                    _kindFilter = MediaLibraryKindFilter.all;
                                    _statusFilter =
                                        MediaLibraryStatusFilter.all;
                                    _productionYear = null;
                                  });
                                  await _reloadCurrentNode();
                                }
                              : null,
                        )
                      else ...[
                        _MediaGrid(
                          items: _items,
                          density: _density,
                          selectionMode: _selectionMode,
                          selectedIds: _selectedIds,
                          onOpen: _openItem,
                          onToggleSelection: _toggleSelection,
                          onEnterSelection: _enterSelectionMode,
                          selectionAvailable: _selectedLibrary?.isLocal != true,
                        ),
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

  Future<void> _changeSort(MediaLibrarySort sort) async {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    await _reloadCurrentNode();
  }

  Future<void> _showFilters() async {
    final result = await showDialog<_LibraryFilters>(
      context: context,
      builder: (context) => _LibraryFilterDialog(
        initialValue: _LibraryFilters(
          kind: _kindFilter,
          status: _statusFilter,
          resolution: _resolutionFilter,
          minCommunityRating: _minCommunityRating,
          productionYear: _productionYear,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (result.kind == _kindFilter &&
        result.status == _statusFilter &&
        result.resolution == _resolutionFilter &&
        result.minCommunityRating == _minCommunityRating &&
        result.productionYear == _productionYear) {
      return;
    }
    setState(() {
      _kindFilter = result.kind;
      _statusFilter = result.status;
      _resolutionFilter = result.resolution;
      _minCommunityRating = result.minCommunityRating;
      _productionYear = result.productionYear;
    });
    await _reloadCurrentNode();
  }

  void _setDensity(MediaGridDensity density) {
    if (_density == density) return;
    setState(() => _density = density);
  }

  void _enterSelectionMode([String? itemId]) {
    setState(() {
      _selectionMode = true;
      if (itemId != null) _selectedIds = {..._selectedIds, itemId};
    });
  }

  void _exitSelectionMode() {
    if (_bulkActionLabel != null) return;
    setState(() {
      _selectionMode = false;
      _selectedIds = {};
    });
  }

  void _toggleSelection(String itemId) {
    setState(() {
      final next = {..._selectedIds};
      if (!next.add(itemId)) next.remove(itemId);
      _selectedIds = next;
    });
  }

  void _selectAllLoaded() {
    setState(() => _selectedIds = _items.map((item) => item.id).toSet());
  }

  Future<void> _applyBulkState({bool? favorite, bool? played}) async {
    final account = widget.account;
    if (account == null || _selectedIds.isEmpty || _bulkActionLabel != null) {
      return;
    }
    final ids = Set<String>.from(_selectedIds);
    final label = favorite != null
        ? favorite
              ? '正在收藏'
              : '正在取消收藏'
        : played == true
        ? '正在标记已观看'
        : '正在标记未观看';
    setState(() => _bulkActionLabel = label);
    try {
      final service = ref.read(mediaLibraryProvider);
      if (favorite != null) {
        await service.setFavoriteForItems(account, ids, favorite: favorite);
      } else {
        await service.setPlayedForItems(account, ids, played: played!);
      }
      if (!mounted) return;
      setState(() {
        _items = _items
            .map(
              (item) => ids.contains(item.id)
                  ? item.copyWith(
                      played: played,
                      favorite: favorite,
                      resumePosition: played == true
                          ? Duration.zero
                          : item.resumePosition,
                    )
                  : item,
            )
            .toList(growable: false);
        _selectionMode = false;
        _selectedIds = {};
      });
      final completedLabel = favorite != null
          ? favorite
                ? '已收藏 ${ids.length} 项'
                : '已取消收藏 ${ids.length} 项'
          : played == true
          ? '已将 ${ids.length} 项标记为已观看'
          : '已将 ${ids.length} 项标记为未观看';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(completedLabel),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => _undoBulkState(
                ids,
                favorite: favorite == null ? null : !favorite,
                played: played == null ? null : !played,
              ),
            ),
          ),
        );
      if (_statusFilter != MediaLibraryStatusFilter.all) {
        await _reloadCurrentNode();
      }
    } on MediaLibraryException catch (error) {
      if (!mounted) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('批量操作失败：${error.message}')));
    } finally {
      if (mounted) setState(() => _bulkActionLabel = null);
    }
  }

  Future<void> _undoBulkState(
    Set<String> ids, {
    bool? favorite,
    bool? played,
  }) async {
    final account = widget.account;
    if (account == null) return;
    try {
      final service = ref.read(mediaLibraryProvider);
      if (favorite != null) {
        await service.setFavoriteForItems(account, ids, favorite: favorite);
      } else {
        await service.setPlayedForItems(account, ids, played: played!);
      }
      if (!mounted) return;
      await _reloadCurrentNode();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已撤销批量操作')));
    } on MediaLibraryException catch (error) {
      if (!mounted) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('撤销失败：${error.message}')));
    }
  }

  int get _activeFilterCount =>
      (_kindFilter == MediaLibraryKindFilter.all ? 0 : 1) +
      (_statusFilter == MediaLibraryStatusFilter.all ? 0 : 1) +
      (_resolutionFilter == MediaResolutionFilter.all ? 0 : 1) +
      (_minCommunityRating == null ? 0 : 1) +
      (_productionYear == null ? 0 : 1);

  bool _isBrowsable(MediaItem item) {
    return item.kind == MediaItemKind.folder ||
        item.kind == MediaItemKind.series ||
        item.kind == MediaItemKind.season;
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.account,
    required this.localLibraryCount,
    required this.onRefresh,
  });

  final AuthenticatedServer? account;
  final int localLibraryCount;
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
                account == null ? '你的本地放映架' : '晚上好，${account!.userName}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                account == null
                    ? '已连接 $localLibraryCount 个本地文件夹'
                    : '正在浏览 ${account!.server.name} · '
                          '${account!.server.kind.label} ${account!.server.version}'
                          '${localLibraryCount == 0 ? '' : '，以及 $localLibraryCount 个本地文件夹'}',
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

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    super.key,
    required this.sort,
    required this.density,
    required this.activeFilterCount,
    required this.onSortChanged,
    required this.onFilterPressed,
    required this.onDensityChanged,
    required this.onSelectPressed,
  });

  final MediaLibrarySort sort;
  final MediaGridDensity density;
  final int activeFilterCount;
  final ValueChanged<MediaLibrarySort> onSortChanged;
  final VoidCallback onFilterPressed;
  final ValueChanged<MediaGridDensity> onDensityChanged;
  final VoidCallback? onSelectPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<MediaLibrarySort>(
          key: const ValueKey('library-sort-menu'),
          initialValue: sort,
          tooltip: '更改排序方式',
          onSelected: onSortChanged,
          itemBuilder: (context) => [
            for (final option in MediaLibrarySort.values)
              PopupMenuItem(
                value: option,
                child: Row(
                  children: [
                    Icon(
                      option == sort
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color: option == sort
                          ? AppColors.spotlight
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 10),
                    Text(option.label),
                  ],
                ),
              ),
          ],
          child: _ToolbarControl(
            icon: Icons.sort_rounded,
            label: '排序：${sort.label}',
          ),
        ),
        Semantics(
          button: true,
          label: activeFilterCount == 0
              ? '筛选媒体'
              : '筛选媒体，已启用 $activeFilterCount 项',
          child: _ToolbarAction(
            key: const ValueKey('library-filter-button'),
            icon: Icons.tune_rounded,
            label: activeFilterCount == 0 ? '筛选' : '筛选 · $activeFilterCount',
            selected: activeFilterCount > 0,
            onPressed: onFilterPressed,
          ),
        ),
        _DensityControl(value: density, onChanged: onDensityChanged),
        if (onSelectPressed != null)
          _ToolbarAction(
            key: const ValueKey('library-select-button'),
            icon: Icons.checklist_rounded,
            label: '选择',
            onPressed: onSelectPressed!,
          ),
      ],
    );
  }
}

class _ToolbarControl extends StatelessWidget {
  const _ToolbarControl({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppGlass.decoration(radius: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 5),
          const Icon(Icons.expand_more_rounded, size: 17),
        ],
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: selected
            ? AppColors.spotlight.withValues(alpha: 0.12)
            : null,
        foregroundColor: selected ? AppColors.spotlight : null,
      ),
      icon: Icon(icon, size: 19),
      label: Text(label),
    );
  }
}

class _DensityControl extends StatelessWidget {
  const _DensityControl({required this.value, required this.onChanged});

  final MediaGridDensity value;
  final ValueChanged<MediaGridDensity> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('library-density-control'),
      padding: const EdgeInsets.all(3),
      decoration: AppGlass.decoration(radius: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DensityButton(
            tooltip: '宽松视图',
            icon: Icons.grid_view_rounded,
            selected: value == MediaGridDensity.spacious,
            onPressed: () => onChanged(MediaGridDensity.spacious),
          ),
          _DensityButton(
            tooltip: '标准视图',
            icon: Icons.apps_rounded,
            selected: value == MediaGridDensity.standard,
            onPressed: () => onChanged(MediaGridDensity.standard),
          ),
          _DensityButton(
            tooltip: '紧凑视图',
            icon: Icons.view_comfy_alt_rounded,
            selected: value == MediaGridDensity.compact,
            onPressed: () => onChanged(MediaGridDensity.compact),
          ),
        ],
      ),
    );
  }
}

class _DensityButton extends StatelessWidget {
  const _DensityButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: tooltip,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          backgroundColor: selected
              ? AppColors.spotlight.withValues(alpha: 0.16)
              : Colors.transparent,
          foregroundColor: selected
              ? AppColors.spotlight
              : AppColors.textSecondary,
        ),
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    super.key,
    required this.selectedCount,
    required this.allLoadedSelected,
    required this.busyLabel,
    required this.favoriteTarget,
    required this.playedTarget,
    required this.onSelectAll,
    required this.onFavorite,
    required this.onPlayed,
    required this.onClose,
  });

  final int selectedCount;
  final bool allLoadedSelected;
  final String? busyLabel;
  final bool favoriteTarget;
  final bool playedTarget;
  final VoidCallback onSelectAll;
  final VoidCallback onFavorite;
  final VoidCallback onPlayed;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final busy = busyLabel != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppGlass.decoration(radius: 14, selected: true),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 20,
              color: AppColors.spotlight,
            ),
          Text(
            busy ? '$busyLabel…' : '已选择 $selectedCount 项',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextButton.icon(
            onPressed: busy || allLoadedSelected ? null : onSelectAll,
            icon: const Icon(Icons.select_all_rounded, size: 18),
            label: const Text('全选已加载'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('bulk-favorite-button'),
            onPressed: busy || selectedCount == 0 ? null : onFavorite,
            icon: Icon(
              favoriteTarget
                  ? Icons.favorite_border_rounded
                  : Icons.heart_broken_rounded,
              size: 18,
            ),
            label: Text(favoriteTarget ? '收藏' : '取消收藏'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('bulk-played-button'),
            onPressed: busy || selectedCount == 0 ? null : onPlayed,
            icon: Icon(
              playedTarget ? Icons.done_all_rounded : Icons.remove_done_rounded,
              size: 18,
            ),
            label: Text(playedTarget ? '标为已观看' : '标为未观看'),
          ),
          IconButton(
            tooltip: '退出批量选择',
            onPressed: busy ? null : onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _LibraryFilters {
  const _LibraryFilters({
    required this.kind,
    required this.status,
    this.resolution = MediaResolutionFilter.all,
    this.minCommunityRating,
    required this.productionYear,
  });

  final MediaLibraryKindFilter kind;
  final MediaLibraryStatusFilter status;
  final MediaResolutionFilter resolution;
  final double? minCommunityRating;
  final int? productionYear;
}

class _LibraryFilterDialog extends StatefulWidget {
  const _LibraryFilterDialog({required this.initialValue});

  final _LibraryFilters initialValue;

  @override
  State<_LibraryFilterDialog> createState() => _LibraryFilterDialogState();
}

class _LibraryFilterDialogState extends State<_LibraryFilterDialog> {
  late MediaLibraryKindFilter _kind = widget.initialValue.kind;
  late MediaLibraryStatusFilter _status = widget.initialValue.status;
  late MediaResolutionFilter _resolution = widget.initialValue.resolution;
  late double? _minCommunityRating = widget.initialValue.minCommunityRating;
  late final TextEditingController _yearController = TextEditingController(
    text: widget.initialValue.productionYear?.toString() ?? '',
  );
  String? _yearError;

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  void _apply() {
    final text = _yearController.text.trim();
    final year = text.isEmpty ? null : int.tryParse(text);
    final maxYear = DateTime.now().year + 1;
    if (text.isNotEmpty && (year == null || year < 1888 || year > maxYear)) {
      setState(() => _yearError = '请输入 1888–$maxYear 之间的年份');
      return;
    }
    Navigator.of(context).pop(
      _LibraryFilters(
        kind: _kind,
        status: _status,
        resolution: _resolution,
        minCommunityRating: _minCommunityRating,
        productionYear: year,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('筛选媒体库'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('内容类型', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in MediaLibraryKindFilter.values)
                    FilterChip(
                      label: Text(option.label),
                      selected: _kind == option,
                      onSelected: (_) => setState(() => _kind = option),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const Text('观看状态', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in MediaLibraryStatusFilter.values)
                    FilterChip(
                      label: Text(option.label),
                      selected: _status == option,
                      onSelected: (_) => setState(() => _status = option),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const Text('画质规格', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in MediaResolutionFilter.values)
                    FilterChip(
                      label: Text(option.label),
                      selected: _resolution == option,
                      onSelected: (_) => setState(() => _resolution = option),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const Text('最低评分', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final rating in [null, 6.0, 7.0, 8.0])
                    FilterChip(
                      label: Text(
                        rating == null
                            ? '全部评分'
                            : '${rating.toStringAsFixed(1)}+ 分',
                      ),
                      selected: _minCommunityRating == rating,
                      onSelected:
                          (_) => setState(() => _minCommunityRating = rating),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              TextField(
                key: const ValueKey('library-year-filter'),
                controller: _yearController,
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  if (_yearError != null) setState(() => _yearError = null);
                },
                decoration: InputDecoration(
                  labelText: '上映年份',
                  hintText: '留空表示所有年份',
                  errorText: _yearError,
                  prefixIcon: const Icon(Icons.calendar_month_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _kind = MediaLibraryKindFilter.all;
              _status = MediaLibraryStatusFilter.all;
              _resolution = MediaResolutionFilter.all;
              _minCommunityRating = null;
              _yearController.clear();
              _yearError = null;
            });
          },
          child: const Text('重置'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _apply, child: const Text('应用筛选')),
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
        final cardWidth = constraints.maxWidth < 640
            ? (constraints.maxWidth * 0.76).clamp(220.0, 300.0)
            : 210.0;
        return PeekHorizontalRail(
          railId: 'library-selector',
          semanticLabel: '选择媒体库',
          height: 86,
          itemCount: libraries.length,
          itemExtent: cardWidth,
          spacing: 12,
          itemBuilder: (context, index) {
            final library = libraries[index];
            return _LibraryChoice(
              library: library,
              selected: library.id == selectedId,
              onSelected: onSelected,
            );
          },
        );
      },
    );
  }
}

class _LibraryChoice extends StatelessWidget {
  const _LibraryChoice({
    required this.library,
    required this.selected,
    required this.onSelected,
  });

  final MediaItem library;
  final bool selected;
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
      child: PeekMediaImage(
        uri: item.imageUri,
        headers: item.imageHeaders,
        kind: PeekMediaImageKind.library,
        placeholderBackground: selected
            ? AppColors.spotlight.withValues(alpha: 0.12)
            : AppColors.surfaceHigh,
        placeholderIconColor: selected
            ? AppColors.spotlight
            : AppColors.textTertiary,
        placeholderIconSize: 22,
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.items,
    required this.density,
    required this.selectionMode,
    required this.selectedIds,
    required this.onOpen,
    required this.onToggleSelection,
    required this.onEnterSelection,
    this.selectionAvailable = true,
  });

  final List<MediaItem> items;
  final MediaGridDensity density;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<MediaItem> onOpen;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterSelection;
  final bool selectionAvailable;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseColumns = switch (constraints.maxWidth) {
          < 520 => 2,
          < 780 => 3,
          < 1040 => 4,
          < 1240 => 5,
          _ => 6,
        };
        final densityOffset = switch (density) {
          MediaGridDensity.spacious => -1,
          MediaGridDensity.standard => 0,
          MediaGridDensity.compact => 1,
        };
        final columns = (baseColumns + densityOffset).clamp(2, 7);
        final spacing = switch (density) {
          MediaGridDensity.spacious => 18.0,
          MediaGridDensity.standard => 14.0,
          MediaGridDensity.compact => 10.0,
        };
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing + 6,
            childAspectRatio: density == MediaGridDensity.compact ? 0.64 : 0.62,
          ),
          itemBuilder: (context, index) => _MediaCard(
            item: items[index],
            selectionMode: selectionMode,
            selected: selectedIds.contains(items[index].id),
            onOpen: () => onOpen(items[index]),
            onToggleSelection: () => onToggleSelection(items[index].id),
            onEnterSelection: selectionAvailable
                ? () => onEnterSelection(items[index].id)
                : null,
          ),
        );
      },
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.onOpen,
    required this.onToggleSelection,
    required this.onEnterSelection,
  });

  final MediaItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onToggleSelection;
  final VoidCallback? onEnterSelection;

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
    return Peek3DCard(
      onTap: selectionMode ? onToggleSelection : onOpen,
      child: Semantics(
        label: '${item.name}，${_kindLabel(item.kind)}',
        button: true,
        selected: selected,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Material(
                key: ValueKey('media-card-artwork-${item.id}'),
                color: AppColors.surfaceLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: selected
                      ? const BorderSide(color: AppColors.spotlight, width: 2)
                      : BorderSide.none,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: selectionMode ? onToggleSelection : onOpen,
                  onLongPress: selectionMode
                    ? onToggleSelection
                    : onEnterSelection,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _MediaArtwork(item: item),
                    if (selectionMode)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _SelectionBadge(selected: selected),
                      )
                    else if (item.favorite)
                      const Positioned(
                        top: 10,
                        left: 10,
                        child: _FavoriteBadge(),
                      ),
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
    return PeekMediaImage(
      uri: item.imageUri,
      headers: item.imageHeaders,
      kind: PeekMediaImageKind.poster,
      fit: BoxFit.cover,
      placeholderIcon: _kindIcon(item.kind),
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

class _FavoriteBadge extends StatelessWidget {
  const _FavoriteBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.canvas.withValues(alpha: 0.84),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.favorite_rounded,
        color: AppColors.spotlight,
        size: 17,
      ),
    );
  }
}

class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.fast,
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: selected ? AppColors.spotlight : Colors.black54,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.spotlight : AppColors.textPrimary,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: AppColors.canvas, size: 19)
          : null,
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
  const _EmptyLibrary({this.filtered = false, this.onClearFilters});

  final bool filtered;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            filtered ? Icons.filter_alt_off_rounded : Icons.inbox_outlined,
            size: 34,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            filtered ? '没有符合当前筛选条件的内容' : '这个媒体库暂时没有可显示的内容',
            textAlign: TextAlign.center,
          ),
          if (filtered && onClearFilters != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('清除筛选'),
            ),
          ],
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
  final VoidCallback? onAction;
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
          if (onAction != null) ...[
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: Icon(
                actionLabel.contains('添加')
                    ? Icons.create_new_folder_outlined
                    : Icons.refresh_rounded,
              ),
              label: Text(actionLabel),
            ),
          ],
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

bool _sameLocalLibraries(
  List<LocalMediaLibrary> left,
  List<LocalMediaLibrary> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].id != right[index].id ||
        left[index].path != right[index].path) {
      return false;
    }
  }
  return true;
}

String _kindLabel(MediaItemKind kind) {
  return switch (kind) {
    MediaItemKind.movie => '电影',
    MediaItemKind.series => '剧集',
    MediaItemKind.season => '季',
    MediaItemKind.episode => '单集',
    MediaItemKind.video => '视频',
    MediaItemKind.audio => '音乐',
    MediaItemKind.person => '人物',
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
    MediaItemKind.person => Icons.person_outline_rounded,
    MediaItemKind.folder => Icons.folder_outlined,
  };
}
