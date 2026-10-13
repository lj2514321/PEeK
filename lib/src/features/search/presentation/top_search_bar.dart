import 'dart:async';
import 'dart:ui';

import 'package:embyplayer/src/app/app_routes.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Clean, lightweight top search bar with VisionOS liquid glass dropdown panel.
class TopSearchBar extends ConsumerStatefulWidget {
  const TopSearchBar({super.key, required this.account, this.compact = false});

  final AuthenticatedServer? account;
  final bool compact;

  @override
  ConsumerState<TopSearchBar> createState() => TopSearchBarState();
}

class TopSearchBarState extends ConsumerState<TopSearchBar> {
  static const _searchDelay = Duration(milliseconds: 300);

  final _queryController = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();

  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  List<MediaItem> _items = const [];
  List<String> _history = const [];
  int _requestGeneration = 0;
  bool _loading = false;
  String? _error;
  bool _isDropdownOpen = false;

  bool get _hasQuery => _queryController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    Future<void>.microtask(_loadHistory);
  }

  @override
  void didUpdateWidget(covariant TopSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account?.userId != widget.account?.userId ||
        oldWidget.account?.server.serverId != widget.account?.server.serverId) {
      _requestGeneration++;
      _debounce?.cancel();
      setState(() {
        _items = const [];
        _loading = false;
        _error = null;
      });
      if (_hasQuery) _search();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _isDropdownOpen = false;
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
    _queryController.dispose();
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  void focus() {
    if (!mounted) return;
    _focusNode.requestFocus();
    _queryController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _queryController.text.length,
    );
    _openDropdown();
  }

  void unfocus() {
    if (!mounted) return;
    _focusNode.unfocus();
    _closeDropdown();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _openDropdown();
    }
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
    _overlayEntry?.markNeedsBuild();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _requestGeneration++;
      setState(() {
        _items = const [];
        _loading = false;
        _error = null;
      });
      _overlayEntry?.markNeedsBuild();
      return;
    }
    _debounce = Timer(_searchDelay, _search);
  }

  Future<void> _search() async {
    final account = widget.account;
    final query = _queryController.text.trim();
    if (account == null || query.isEmpty) {
      setState(() {
        _items = const [];
        _loading = false;
      });
      _overlayEntry?.markNeedsBuild();
      return;
    }

    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    _overlayEntry?.markNeedsBuild();

    try {
      final page = await ref
          .read(mediaLibraryProvider)
          .search(account, query: query, limit: 20);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _items = page.items;
      });
    } on MediaLibraryException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = error.message);
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
        _overlayEntry?.markNeedsBuild();
      }
    }
  }

  void _useHistory(String query) {
    _queryController.text = query;
    _queryController.selection = TextSelection.collapsed(offset: query.length);
    _onQueryChanged(query);
  }

  void _selectItem(MediaItem item) {
    _rememberQuery();
    _closeDropdown();
    _focusNode.unfocus();

    final account = widget.account;
    if (account == null) return;

    if (item.kind == MediaItemKind.person) {
      AppRoutes.openPersonWorks(
        context,
        account: account,
        person: MediaPerson(
          id: item.id,
          name: item.name,
          type: 'Actor',
          imageUri: item.imageUri,
          imageHeaders: item.imageHeaders,
        ),
        onOpen: (work) =>
            AppRoutes.openMediaDetail(context, account: account, item: work),
      );
      return;
    }

    AppRoutes.openMediaDetail(context, account: account, item: item);
  }

  void _openDropdown() {
    if (_isDropdownOpen) return;
    _isDropdownOpen = true;

    _overlayEntry = OverlayEntry(
      builder: (context) => _SearchDropdownOverlay(
        layerLink: _layerLink,
        queryController: _queryController,
        focusNode: _focusNode,
        items: _items,
        history: _history,
        loading: _loading,
        error: _error,
        account: widget.account,
        onHistorySelected: _useHistory,
        onClearHistory: _clearHistory,
        onItemSelected: _selectItem,
        onDismiss: () {
          _closeDropdown();
          _focusNode.unfocus();
        },
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _closeDropdown() {
    if (!_isDropdownOpen) return;
    _isDropdownOpen = false;
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return CompositedTransformTarget(
        link: _layerLink,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: AppRadius.borderRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
          ),
          child: IconButton(
            tooltip: '搜索媒体库（Ctrl+K）',
            visualDensity: VisualDensity.compact,
            onPressed: focus,
            icon: const Icon(Icons.search_rounded, size: 18),
          ),
        ),
      );
    }

    final hasFocus = _focusNode.hasFocus;
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: focus,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: const Cubic(0.16, 1.0, 0.3, 1.0),
          width: hasFocus ? 320 : 260,
          height: 36,
          decoration: BoxDecoration(
            color: hasFocus
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: AppRadius.borderRadius,
            border: Border.all(
              color: hasFocus
                  ? Colors.white.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.28),
              width: 1.1,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.16),
                      blurRadius: 16,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(
                Icons.search_rounded,
                size: 16,
                color: hasFocus ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('top-search-field'),
                  controller: _queryController,
                  focusNode: _focusNode,
                  onTap: focus,
                  onChanged: _onQueryChanged,
                  onSubmitted: (_) {
                    _search();
                    _rememberQuery();
                  },
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    hintText: '搜索电影、剧集与人物...',
                    hintStyle: TextStyle(color: Colors.white70, fontSize: 12),
                    isDense: true,
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (_hasQuery)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: AppRadius.borderRadius,
                    onTap: () {
                      _queryController.clear();
                      _onQueryChanged('');
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: _ShortcutBadge(label: 'Ctrl K'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// VisionOS Liquid Glass dropdown overlay panel.
class _SearchDropdownOverlay extends StatelessWidget {
  const _SearchDropdownOverlay({
    required this.layerLink,
    required this.queryController,
    required this.focusNode,
    required this.items,
    required this.history,
    required this.loading,
    required this.error,
    required this.account,
    required this.onHistorySelected,
    required this.onClearHistory,
    required this.onItemSelected,
    required this.onDismiss,
  });

  final LayerLink layerLink;
  final TextEditingController queryController;
  final FocusNode focusNode;
  final List<MediaItem> items;
  final List<String> history;
  final bool loading;
  final String? error;
  final AuthenticatedServer? account;
  final ValueChanged<String> onHistorySelected;
  final VoidCallback onClearHistory;
  final ValueChanged<MediaItem> onItemSelected;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final panelWidth = screenSize.width < 440 ? screenSize.width - 32 : 380.0;
    final maxPanelHeight = (screenSize.height - 120).clamp(200.0, 460.0);
    final query = queryController.text.trim();

    final barrier = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onDismiss,
      child: Container(color: Colors.black.withValues(alpha: 0.16)),
    );

    final panel = ClipRRect(
      borderRadius: AppRadius.borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
        child: Container(
          key: const ValueKey('search-dropdown-panel'),
          constraints: BoxConstraints(maxHeight: maxPanelHeight),
          decoration: BoxDecoration(
            color: const Color(0x8A121A2E),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.24),
                Colors.white.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: AppRadius.borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.36),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.42),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: _buildContent(context, query),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        // Dismiss tap barrier with smooth fade-in
        Positioned.fill(
          child: AppMotion.isTest
              ? barrier
              : barrier.animate().fadeIn(
                  duration: const Duration(milliseconds: 160),
                ),
        ),
        // Liquid Glass Dropdown "半框" with fluid spring/bounce animation
        Positioned(
          width: panelWidth,
          child: CompositedTransformFollower(
            link: layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            child: AppMotion.isTest
                ? panel
                : panel
                      .animate()
                      .fadeIn(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutQuad,
                      )
                      .slideY(
                        begin: -0.06,
                        end: 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                      )
                      .scale(
                        begin: const Offset(0.96, 0.96),
                        end: const Offset(1.0, 1.0),
                        alignment: Alignment.topRight,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, String query) {
    if (account == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Center(
          child: Text(
            '请先连接服务器后再进行搜索',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ),
      );
    }

    if (query.isEmpty) {
      return _buildHistoryOrEmpty(context);
    }

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              color: AppColors.spotlight,
            ),
          ),
        ),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Center(
          child: Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error, fontSize: 12),
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        child: Center(
          child: Text(
            '未找到相关内容',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
          ),
        ),
      );
    }

    return PeekSmoothScroll(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return PeekStaggeredGridItem(
            key: ValueKey('search-stagger-$index-${item.id}'),
            index: index,
            columns: 1,
            child: _SearchResultTile(
              item: item,
              account: account!,
              onTap: () => onItemSelected(item),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryOrEmpty(BuildContext context) {
    if (history.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Center(
          child: Text(
            '输入片名、演员或导演开始搜索',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 13,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 5),
              const Text(
                '最近搜索',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onClearHistory,
                child: const Text(
                  '清空',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final q in history)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onHistorySelected(q),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      q,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.item,
    required this.account,
    required this.onTap,
  });

  final MediaItem item;
  final AuthenticatedServer account;
  final VoidCallback onTap;

  String _typeLabel(MediaItemKind kind) {
    return switch (kind) {
      MediaItemKind.movie => '电影',
      MediaItemKind.series => '剧集',
      MediaItemKind.season => '季',
      MediaItemKind.episode => '单集',
      MediaItemKind.person => '人物',
      MediaItemKind.folder => '分类',
      MediaItemKind.video => '视频',
      MediaItemKind.audio => '音频',
    };
  }

  @override
  Widget build(BuildContext context) {
    final typeBadge = _typeLabel(item.kind);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            // Poster / avatar
            ClipRRect(
              borderRadius: BorderRadius.circular(
                item.kind == MediaItemKind.person ? 18 : 6,
              ),
              child: SizedBox(
                width: item.kind == MediaItemKind.person ? 36 : 32,
                height: item.kind == MediaItemKind.person ? 36 : 44,
                child: item.kind == MediaItemKind.person
                    ? PeekMediaImage(
                        uri: item.imageUri,
                        headers: item.imageHeaders,
                        kind: PeekMediaImageKind.person,
                        fit: BoxFit.cover,
                        placeholderBackground: Colors.white.withValues(
                          alpha: 0.06,
                        ),
                        placeholderIcon: Icons.person_rounded,
                        placeholderIconSize: 20,
                        placeholderIconColor: AppColors.textTertiary,
                      )
                    : PeekMediaImage(
                        uri: item.imageUri,
                        headers: item.imageHeaders,
                        kind: PeekMediaImageKind.poster,
                        fit: BoxFit.cover,
                        placeholderBackground: Colors.white.withValues(
                          alpha: 0.06,
                        ),
                        placeholderIcon: Icons.movie_outlined,
                        placeholderIconSize: 18,
                        placeholderIconColor: AppColors.textTertiary,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            // Title & compact metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        typeBadge,
                        style: const TextStyle(
                          color: AppColors.spotlight,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (item.productionYear != null) ...[
                        const SizedBox(width: 5),
                        const Text(
                          '·',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${item.productionYear}',
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 10.5,
                            fontFamily: 'Cascadia Mono',
                          ),
                        ),
                      ],
                      if (item.communityRating != null) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.star_rounded,
                          size: 11,
                          color: Color(0xFFFFB800),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          item.communityRating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Cascadia Mono',
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutBadge extends StatelessWidget {
  const _ShortcutBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 9.5,
          fontFamily: 'Cascadia Mono',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
