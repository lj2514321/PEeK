import 'dart:async';

import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MediaSearchPage extends ConsumerStatefulWidget {
  const MediaSearchPage({
    super.key,
    required this.account,
    required this.onGoHome,
    this.onSessionExpired,
  });

  final AuthenticatedServer? account;
  final VoidCallback onGoHome;
  final VoidCallback? onSessionExpired;

  @override
  ConsumerState<MediaSearchPage> createState() => MediaSearchPageState();
}

class MediaSearchPageState extends ConsumerState<MediaSearchPage> {
  static const _pageSize = 40;
  static const _searchDelay = Duration(milliseconds: 350);

  final _queryController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();

  Timer? _debounce;
  List<MediaItem> _items = const [];
  List<String> _history = const [];
  MediaSearchScope _scope = MediaSearchScope.all;
  MediaItem? _personContext;
  String? _queryBeforePerson;
  int _totalItemCount = 0;
  int _nextStartIndex = 0;
  int _requestGeneration = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _searchFieldFocused = false;
  String? _error;
  String? _paginationError;

  bool get _hasQuery => _queryController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearEnd);
    _searchFocusNode.addListener(_handleFocusChange);
    Future<void>.microtask(_loadHistory);
  }

  @override
  void didUpdateWidget(covariant MediaSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.account;
    final current = widget.account;
    if (previous?.userId == current?.userId &&
        previous?.server.serverId == current?.server.serverId) {
      return;
    }
    _requestGeneration++;
    _debounce?.cancel();
    setState(() {
      _items = const [];
      _personContext = null;
      _queryBeforePerson = null;
      _totalItemCount = 0;
      _nextStartIndex = 0;
      _loading = false;
      _loadingMore = false;
      _error = null;
      _paginationError = null;
    });
    if (current != null && _hasQuery) _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _searchFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void focusSearch() {
    if (!mounted || widget.account == null) return;
    _searchFocusNode.requestFocus();
    _queryController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _queryController.text.length,
    );
  }

  void _handleFocusChange() {
    if (!mounted || _searchFieldFocused == _searchFocusNode.hasFocus) return;
    setState(() => _searchFieldFocused = _searchFocusNode.hasFocus);
  }

  Future<void> _loadHistory() async {
    final history = await ref.read(searchHistoryStoreProvider).read();
    if (mounted) setState(() => _history = history);
  }

  Future<void> _rememberQuery([String? query]) async {
    final value = (query ?? _queryController.text).trim();
    if (value.isEmpty) return;
    final history = await ref.read(searchHistoryStoreProvider).add(value);
    if (mounted) setState(() => _history = history);
  }

  Future<void> _clearHistory() async {
    await ref.read(searchHistoryStoreProvider).clear();
    if (mounted) setState(() => _history = const []);
  }

  void _onQueryChanged(String value) {
    if (_personContext != null) {
      setState(() {
        _personContext = null;
        _queryBeforePerson = null;
      });
    }
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _requestGeneration++;
      setState(() {
        _items = const [];
        _totalItemCount = 0;
        _nextStartIndex = 0;
        _loading = false;
        _loadingMore = false;
        _error = null;
        _paginationError = null;
      });
      return;
    }
    _debounce = Timer(_searchDelay, _search);
  }

  void _submitQuery(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) return;
    unawaited(_rememberQuery(value));
    _search();
  }

  void _selectScope(MediaSearchScope scope) {
    if (_scope == scope && _personContext == null) return;
    setState(() {
      _scope = scope;
      _personContext = null;
      _queryBeforePerson = null;
    });
    if (_hasQuery) _search();
  }

  Future<void> _useHistory(String query) async {
    _debounce?.cancel();
    _queryController
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    await _rememberQuery(query);
    if (mounted) await _search();
  }

  Future<void> _search({bool forceRefresh = false}) async {
    final account = widget.account;
    final query = _queryController.text.trim();
    if (account == null || query.isEmpty) return;
    final generation = ++_requestGeneration;
    setState(() {
      _personContext = null;
      _queryBeforePerson = null;
      _items = const [];
      _totalItemCount = 0;
      _nextStartIndex = 0;
      _loading = true;
      _loadingMore = false;
      _error = null;
      _paginationError = null;
    });

    try {
      final page = await ref
          .read(mediaLibraryProvider)
          .search(
            account,
            query: query,
            scope: _scope,
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
    final person = _personContext;
    final query = _queryController.text.trim();
    setState(() {
      _loadingMore = true;
      _paginationError = null;
    });
    try {
      final service = ref.read(mediaLibraryProvider);
      final page = person == null
          ? await service.search(
              account,
              query: query,
              scope: _scope,
              startIndex: _nextStartIndex,
              limit: _pageSize,
            )
          : await service.getItemsForPerson(
              account,
              personId: person.id,
              startIndex: _nextStartIndex,
              limit: _pageSize,
            );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _items = [..._items, ...page.items];
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
    if (item.kind == MediaItemKind.person) {
      await _openPerson(item);
      return;
    }
    final account = widget.account;
    if (account == null) return;
    await _rememberQuery();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            MediaDetailPage(account: account, initialItem: item),
      ),
    );
  }

  Future<void> _openPerson(MediaItem person) async {
    final account = widget.account;
    if (account == null) return;
    final previousQuery = _queryController.text.trim();
    await _rememberQuery(previousQuery);
    if (!mounted) return;
    final generation = ++_requestGeneration;
    setState(() {
      _personContext = person;
      _queryBeforePerson = previousQuery;
      _items = const [];
      _totalItemCount = 0;
      _nextStartIndex = 0;
      _loading = true;
      _loadingMore = false;
      _error = null;
      _paginationError = null;
    });
    if (_scrollController.hasClients) {
      unawaited(
        _scrollController.animateTo(
          0,
          duration: AppMotion.responsive(context, AppMotion.standard),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    try {
      final page = await ref
          .read(mediaLibraryProvider)
          .getItemsForPerson(account, personId: person.id, limit: _pageSize);
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
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _leavePerson() async {
    final query = _queryBeforePerson ?? '';
    _queryController
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    setState(() {
      _personContext = null;
      _queryBeforePerson = null;
    });
    if (query.isNotEmpty) await _search();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.account == null) {
      return _SearchAccessState(onGoHome: widget.onGoHome);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 720 ? 20.0 : 32.0;
        final contentWidth = constraints.maxWidth - horizontalPadding * 2;
        final columns = switch (contentWidth) {
          < 480 => 2,
          < 720 => 3,
          < 960 => 4,
          < 1180 => 5,
          _ => 6,
        };
        return CustomScrollView(
          key: const PageStorageKey('media-search-scroll'),
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                28,
                horizontalPadding,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: _buildHeader(context),
                  ),
                ),
              ),
            ),
            ..._buildContentSlivers(
              context,
              horizontalPadding: horizontalPadding,
              columns: columns,
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SEARCH THE LIBRARY',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 9),
        Text('找到今晚想看的内容', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          '搜索电影、剧集、单集与演员，结果直接来自当前媒体服务器。',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('media-search-field'),
                controller: _queryController,
                focusNode: _searchFocusNode,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: _submitQuery,
                decoration: InputDecoration(
                  hintText: '输入片名、剧集或演员名',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _hasQuery
                      ? IconButton(
                          tooltip: '清空搜索',
                          onPressed: () {
                            _queryController.clear();
                            _onQueryChanged('');
                            focusSearch();
                          },
                          icon: const Icon(Icons.close_rounded),
                        )
                      : null,
                ),
              ),
              AnimatedContainer(
                duration: AppMotion.responsive(context, AppMotion.fast),
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _searchFieldFocused
                        ? const [
                            Colors.transparent,
                            AppColors.indigo,
                            AppColors.spotlight,
                            Colors.transparent,
                          ]
                        : const [Colors.transparent, Colors.transparent],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final scope in MediaSearchScope.values)
              ChoiceChip(
                label: Text(_scopeLabel(scope)),
                selected: _scope == scope,
                showCheckmark: false,
                side: BorderSide.none,
                backgroundColor: AppColors.surfaceLow,
                selectedColor: AppColors.glassSelected,
                labelStyle: TextStyle(
                  color: _scope == scope
                      ? AppColors.spotlight
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) => _selectScope(scope),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildContentSlivers(
    BuildContext context, {
    required double horizontalPadding,
    required int columns,
  }) {
    final person = _personContext;
    final contentPadding = EdgeInsets.fromLTRB(
      horizontalPadding,
      26,
      horizontalPadding,
      48,
    );
    if (!_hasQuery && person == null) {
      return [
        SliverPadding(
          padding: contentPadding,
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: _SearchStartState(
                  history: _history,
                  onSelect: _useHistory,
                  onClear: _clearHistory,
                ),
              ),
            ),
          ),
        ),
      ];
    }
    final resultHeader = person == null
        ? _ResultHeader(
            title: _loading ? '正在搜索' : '搜索结果',
            detail: _loading
                ? '正在查询 ${widget.account!.server.name}'
                : '$_totalItemCount 个匹配项',
          )
        : _PersonResultHeader(
            person: person,
            total: _totalItemCount,
            onBack: _leavePerson,
          );

    if (_loading) {
      return [
        SliverPadding(
          padding: contentPadding,
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    resultHeader,
                    const SizedBox(height: 72),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverPadding(
          padding: contentPadding,
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    resultHeader,
                    const SizedBox(height: 18),
                    _SearchErrorState(
                      message: _error!,
                      onRetry: person == null
                          ? _search
                          : () => _openPerson(person),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }
    if (_items.isEmpty) {
      return [
        SliverPadding(
          padding: contentPadding,
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    resultHeader,
                    const SizedBox(height: 18),
                    _SearchEmptyState(person: person),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          26,
          horizontalPadding,
          18,
        ),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: resultHeader,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final spacing = 14.0;
            final width = constraints.crossAxisExtent.clamp(0, 1280).toDouble();
            final cardWidth = (width - spacing * (columns - 1)) / columns;
            final cardHeight = cardWidth / 0.67 + 48;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: 22,
                mainAxisExtent: cardHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _SearchResultCard(
                  item: _items[index],
                  onOpen: () => _openItem(_items[index]),
                ),
                childCount: _items.length,
              ),
            );
          },
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          26,
          horizontalPadding,
          48,
        ),
        sliver: SliverToBoxAdapter(
          child: _PaginationStatus(
            loading: _loadingMore,
            error: _paginationError,
            hasMore: _nextStartIndex < _totalItemCount,
            onRetry: _loadMore,
          ),
        ),
      ),
    ];
  }
}

class _SearchAccessState extends StatelessWidget {
  const _SearchAccessState({required this.onGoHome});

  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: GlassSurface(
          padding: const EdgeInsets.all(32),
          radius: 22,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.manage_search_rounded,
                  color: AppColors.spotlight,
                  size: 48,
                ),
                const SizedBox(height: 18),
                Text(
                  '连接服务器后开始搜索',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 9),
                const Text(
                  '搜索内容来自你的 Jellyfin 或 Emby 媒体库。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onGoHome,
                  icon: const Icon(Icons.dns_rounded),
                  label: const Text('返回并连接服务器'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchStartState extends StatelessWidget {
  const _SearchStartState({
    required this.history,
    required this.onSelect,
    required this.onClear,
  });

  final List<String> history;
  final ValueChanged<String> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                history.isEmpty ? '从一个名字开始' : '最近搜索',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (history.isNotEmpty)
              TextButton(onPressed: onClear, child: const Text('清空记录')),
          ],
        ),
        const SizedBox(height: 12),
        if (history.isEmpty)
          Container(
            padding: const EdgeInsets.all(22),
            decoration: AppGlass.decoration(radius: 18),
            child: const Row(
              children: [
                Icon(Icons.keyboard_rounded, color: AppColors.indigo),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '输入关键词即可实时搜索；以后可随时按 Ctrl+K 回到这里。',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final query in history)
                ActionChip(
                  avatar: const Icon(Icons.history_rounded, size: 17),
                  label: Text(query),
                  side: BorderSide.none,
                  backgroundColor: AppColors.surfaceLow,
                  onPressed: () => onSelect(query),
                ),
            ],
          ),
      ],
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Text(
          detail,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontFamily: 'Cascadia Mono',
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _PersonResultHeader extends StatelessWidget {
  const _PersonResultHeader({
    required this.person,
    required this.total,
    required this.onBack,
  });

  final MediaItem person;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppGlass.decoration(radius: 18, selected: true),
      child: Row(
        children: [
          _PersonAvatar(person: person, size: 58),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${person.name} 的相关作品',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '$total 个媒体条目',
                  style: const TextStyle(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('返回结果'),
          ),
        ],
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isPerson = item.kind == MediaItemKind.person;
    return Semantics(
      button: true,
      label: '${item.name}，${_kindLabel(item.kind)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Material(
              color: AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(15),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onOpen,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _SearchArtwork(item: item),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isPerson ? '查看作品' : '查看详情',
                              style: const TextStyle(fontSize: 10),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.arrow_forward_rounded, size: 13),
                          ],
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
}

class _SearchArtwork extends StatelessWidget {
  const _SearchArtwork({required this.item});

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

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.person, required this.size});

  final MediaItem person;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: PeekMediaImage(
          uri: person.imageUri,
          headers: person.imageHeaders,
          kind: PeekMediaImageKind.person,
          placeholderBackground: AppColors.surfaceHigh,
        ),
      ),
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.error),
          const SizedBox(width: 14),
          Expanded(child: Text(message)),
          const SizedBox(width: 12),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({this.person});

  final MediaItem? person;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: AppGlass.decoration(radius: 18),
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            color: AppColors.textTertiary,
            size: 38,
          ),
          const SizedBox(height: 13),
          Text(
            person == null ? '没有找到匹配内容' : '没有找到相关作品',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            person == null ? '试试更短的关键词，或切换内容类型。' : '服务器中暂时没有关联到这位人物的媒体。',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _PaginationStatus extends StatelessWidget {
  const _PaginationStatus({
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final bool hasMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('$error  点击重试'),
        ),
      );
    }
    if (hasMore) {
      return const Center(
        child: Text(
          '继续滚动加载更多',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

String _scopeLabel(MediaSearchScope scope) => switch (scope) {
  MediaSearchScope.all => '全部',
  MediaSearchScope.movies => '电影',
  MediaSearchScope.series => '剧集',
  MediaSearchScope.episodes => '单集',
  MediaSearchScope.people => '人物',
};

String _kindLabel(MediaItemKind kind) => switch (kind) {
  MediaItemKind.movie => '电影',
  MediaItemKind.series => '剧集',
  MediaItemKind.season => '季',
  MediaItemKind.episode => '单集',
  MediaItemKind.video => '视频',
  MediaItemKind.audio => '音频',
  MediaItemKind.person => '人物',
  MediaItemKind.folder => '文件夹',
};

IconData _kindIcon(MediaItemKind kind) => switch (kind) {
  MediaItemKind.movie => Icons.movie_rounded,
  MediaItemKind.series => Icons.live_tv_rounded,
  MediaItemKind.season => Icons.video_collection_rounded,
  MediaItemKind.episode => Icons.smart_display_rounded,
  MediaItemKind.video => Icons.videocam_rounded,
  MediaItemKind.audio => Icons.graphic_eq_rounded,
  MediaItemKind.person => Icons.person_rounded,
  MediaItemKind.folder => Icons.folder_rounded,
};

String _metadata(MediaItem item) {
  final parts = <String>[_kindLabel(item.kind)];
  if (item.productionYear != null) parts.add('${item.productionYear}');
  if (item.seriesName != null) parts.add(item.seriesName!);
  return parts.join(' · ');
}
