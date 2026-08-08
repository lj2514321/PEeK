import 'package:embyplayer/src/app/app_chrome.dart';
import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
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
  static const _pageSize = 100;

  final _scrollController = ScrollController();
  List<MediaItem> _items = const [];
  List<MediaItem> _libraries = const [];
  int _nextStartIndex = 0;
  int _requestGeneration = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _lastPageShort = false;
  String? _error;
  String? _paginationError;
  String? _librariesError;
  String? _selectedLibraryId;

  // Jellyfin's /Persons endpoint reports TotalRecordCount as the page size,
  // so pagination relies on "keep paging while pages come back full".
  bool get _hasMore => _items.isNotEmpty && !_lastPageShort;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearEnd);
    if (widget.account != null) {
      Future<void>.microtask(_loadActors);
      Future<void>.microtask(_loadLibraries);
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
          _libraries = const [];
          _nextStartIndex = 0;
          _error = null;
          _paginationError = null;
          _librariesError = null;
          _selectedLibraryId = null;
          _lastPageShort = false;
        });
      } else {
        _loadActors();
        _loadLibraries();
      }
    }
  }

  void _selectLibrary(String? libraryId) {
    if (libraryId == _selectedLibraryId) return;
    setState(() {
      _selectedLibraryId = libraryId;
      _items = const [];
      _nextStartIndex = 0;
      _paginationError = null;
      _lastPageShort = false;
    });
    scrollToTop();
    _loadActors();
  }

  Future<void> _loadLibraries() async {
    final account = widget.account;
    if (account == null) return;
    setState(() => _librariesError = null);
    try {
      final libraries = await ref
          .read(mediaLibraryProvider)
          .getLibraries(account);
      if (!mounted) return;
      setState(() => _libraries = libraries);
    } on MediaLibraryException catch (error) {
      if (!mounted) return;
      if (error.authenticationExpired) widget.onSessionExpired?.call();
      setState(() => _librariesError = error.message);
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
          .getActors(
            account,
            parentId: _selectedLibraryId,
            limit: _pageSize,
            forceRefresh: forceRefresh,
          );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _items = page.items;
        _nextStartIndex = page.nextStartIndex;
        _lastPageShort = (page.rawItemCount ?? page.items.length) < _pageSize;
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
    if (account == null || _loading || _loadingMore || _lastPageShort) {
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
          .getActors(
            account,
            parentId: _selectedLibraryId,
            startIndex: _nextStartIndex,
            limit: _pageSize,
          );
      if (!mounted || generation != _requestGeneration) return;
      final previousLength = _items.length;
      final knownIds = _items.map((item) => item.id).toSet();
      final newItems = page.items.where((item) => knownIds.add(item.id))
          .toList(growable: false);
      setState(() {
        _items = [..._items, ...newItems];
        _nextStartIndex = page.nextStartIndex;
        // Stop if the raw page was short OR if no new unique items were added
        // (the server may return duplicate data for different StartIndex values).
        _lastPageShort = (page.rawItemCount ?? page.items.length) < _pageSize
            || _items.length == previousLength;
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
            if (widget.account != null)
              SliverToBoxAdapter(
                child: _LibraryFilterBar(
                  libraries: _libraries,
                  error: _librariesError,
                  selectedLibraryId: _selectedLibraryId,
                  onSelected: _selectLibrary,
                  onRetry: _loadLibraries,
                ),
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

class _LibraryFilterBar extends StatelessWidget {
  const _LibraryFilterBar({
    required this.libraries,
    required this.error,
    required this.selectedLibraryId,
    required this.onSelected,
    required this.onRetry,
  });

  final List<MediaItem> libraries;
  final String? error;
  final String? selectedLibraryId;
  final ValueChanged<String?> onSelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 2),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '无法读取媒体库：$error',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _LibraryChip(
              label: '全部',
              selected: selectedLibraryId == null,
              onTap: () => onSelected(null),
            ),
            for (final library in libraries)
              _LibraryChip(
                label: library.name,
                selected: library.id == selectedLibraryId,
                onTap: () => onSelected(library.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryChip extends StatelessWidget {
  const _LibraryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: AppGlass.decoration(radius: 99, selected: selected),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
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
