import 'dart:io';

import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_3d_card.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/dedupe/data/duplicate_detector_service.dart';
import 'package:embyplayer/src/features/dedupe/data/duplicate_ignored_store.dart';
import 'package:embyplayer/src/features/dedupe/domain/duplicate_media_group.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/player/presentation/playback_page.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MediaDedupePage extends ConsumerStatefulWidget {
  const MediaDedupePage({
    super.key,
    required this.account,
    this.initialItems = const [],
    this.libraryId,
    this.libraryName,
  });

  final AuthenticatedServer? account;
  final List<MediaItem> initialItems;
  final String? libraryId;
  final String? libraryName;

  @override
  ConsumerState<MediaDedupePage> createState() => _MediaDedupePageState();
}

class _MediaDedupePageState extends ConsumerState<MediaDedupePage> {
  final _scrollController = SmoothScrollController();
  List<DuplicateMediaGroup> _groups = [];
  Set<String> _ignoredGroupIds = {};
  bool _scanning = false;
  int _scannedItemCount = 0;
  int _totalItemCount = 0;
  String _scanProgressMessage = '准备扫描媒体库...';
  String _selectedFilter = 'all'; // 'all', 'movie', 'series', 'local'

  @override
  void initState() {
    super.initState();
    _initAndScan();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initAndScan() async {
    setState(() {
      _scanning = true;
      _scannedItemCount = 0;
      _totalItemCount = 0;
      _scanProgressMessage = '正在读取查重白名单配置...';
    });
    final ignoredStore = ref.read(duplicateIgnoredStoreProvider);
    _ignoredGroupIds = await ignoredStore.read();

    List<MediaItem> itemsToScan = [];

    if (widget.account != null) {
      try {
        final libraryService = ref.read(mediaLibraryProvider);
        setState(() => _scanProgressMessage = '正在全面拉取媒体库所有条目及演职员元数据...');
        itemsToScan = await libraryService.fetchAllMediaForDedupe(
          widget.account!,
          parentId: widget.libraryId,
          onProgress: (loaded, total) {
            if (mounted) {
              setState(() {
                _scannedItemCount = loaded;
                _totalItemCount = total;
                _scanProgressMessage = '正在遍历媒体条目: 已拉取 $loaded / $total 项...';
              });
            }
          },
        );
      } catch (_) {
        itemsToScan = widget.initialItems;
      }
    } else {
      itemsToScan = widget.initialItems;
    }

    if (mounted) {
      setState(() => _scanProgressMessage = '正在运行多维特征聚类算法（比对封面、主演、片长与番号）...');
    }

    final detector = ref.read(duplicateDetectorServiceProvider);
    final detected = detector.findDuplicates(
      itemsToScan,
      ignoredGroupIds: _ignoredGroupIds,
    );

    if (mounted) {
      setState(() {
        _scannedItemCount = itemsToScan.length;
        _groups = detected;
        _scanning = false;
      });
    }
  }

  void _toggleDeleteSelection(String groupId, String itemId) {
    setState(() {
      final index = _groups.indexWhere((g) => g.id == groupId);
      if (index == -1) return;
      final group = _groups[index];
      final nextSet = Set<String>.from(group.selectedDeleteIds);
      if (nextSet.contains(itemId)) {
        nextSet.remove(itemId);
      } else {
        nextSet.add(itemId);
      }
      _groups[index] = group.copyWith(selectedDeleteIds: nextSet);
    });
  }

  Future<void> _ignoreGroup(DuplicateMediaGroup group) async {
    final store = ref.read(duplicateIgnoredStoreProvider);
    await store.ignore(group.id);
    setState(() {
      _ignoredGroupIds = {..._ignoredGroupIds, group.id};
      _groups.removeWhere((g) => g.id == group.id);
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text('已将《${group.title}》加入查重白名单'),
          ),
        );
    }
  }

  Future<void> _deleteItem(MediaItem item) async {
    final confirm = await peekShowDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除该文件？'),
        content: Text(
          '即将删除媒体条目《${item.name}》。\n'
          '${item.isLocal ? '本地文件将移至系统回收站。' : '此操作将从媒体服务器中永久删除该条目及关联文件。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (item.isLocal && item.sourcePath != null) {
        final file = File(item.sourcePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } else if (widget.account != null) {
        final libraryService = ref.read(mediaLibraryProvider);
        await libraryService.deleteItem(widget.account!, item.id);
      }

      setState(() {
        for (var i = 0; i < _groups.length; i++) {
          final g = _groups[i];
          final updatedItems = g.items.where((it) => it.item.id != item.id).toList();
          if (updatedItems.length < 2) {
            _groups.removeAt(i);
            i--;
          } else {
            _groups[i] = DuplicateMediaGroup(
              id: g.id,
              title: g.title,
              productionYear: g.productionYear,
              matchReason: g.matchReason,
              matchDetail: g.matchDetail,
              items: updatedItems,
              recommendedKeepId: g.recommendedKeepId == item.id
                  ? updatedItems.first.item.id
                  : g.recommendedKeepId,
              selectedDeleteIds: g.selectedDeleteIds.where((id) => id != item.id).toSet(),
            );
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 2),
              content: Text('已成功删除《${item.name}》'),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('删除失败：$e')),
          );
      }
    }
  }

  void _openDetail(MediaItem item) {
    if (widget.account == null) return;
    Navigator.of(context).push<void>(
      Peek3DPageRoute(
        builder: (context) => MediaDetailPage(
          account: widget.account!,
          initialItem: item,
        ),
      ),
    );
  }

  Future<void> _openPreviewPlayback(MediaItem item) async {
    if (widget.account == null && !item.isLocal) return;
    try {
      final prepared = await ref
          .read(playbackPreparationProvider)
          .prepare(widget.account, item);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        Peek3DPageRoute(
          builder: (context) => PlaybackPage(
            account: widget.account,
            item: prepared.item,
            plan: prepared.plan,
            queue: prepared.queue,
            hardwareDecodingMode: prepared.settings.hardwareDecodingMode,
            maxStreamingBitrate: prepared.settings.maxStreamingBitrate,
            subtitlePreferences: prepared.settings.subtitlePreferences,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('无法开始播放：$e')),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredGroups = _groups.where((g) {
      if (_selectedFilter == 'all') return true;
      if (_selectedFilter == 'movie') {
        return g.items.any((it) => it.item.kind == MediaItemKind.movie);
      }
      if (_selectedFilter == 'series') {
        return g.items.any((it) =>
            it.item.kind == MediaItemKind.series ||
            it.item.kind == MediaItemKind.episode);
      }
      if (_selectedFilter == 'local') {
        return g.items.any((it) => it.item.isLocal);
      }
      return true;
    }).toList();

    var totalSavingsBytes = 0;
    for (final g in filteredGroups) {
      totalSavingsBytes += g.potentialSavingsBytes;
    }
    final formattedSavings = totalSavingsBytes >= 1024 * 1024 * 1024
        ? '${(totalSavingsBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
        : '${(totalSavingsBytes / (1024 * 1024)).toStringAsFixed(0)} MB';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              _buildMetricBar(filteredGroups.length, formattedSavings),
              _buildFilterChips(),
              Expanded(
                child: _scanning
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: AppGlass.decoration(radius: 20),
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 20),
                              Text(
                                _scanProgressMessage,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (_totalItemCount > 0) ...[
                                const SizedBox(height: 14),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (_scannedItemCount / _totalItemCount).clamp(0.0, 1.0),
                                    minHeight: 6,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '已处理 $_scannedItemCount / $_totalItemCount 项',
                                  style: const TextStyle(
                                    fontFamily: 'Cascadia Mono',
                                    fontSize: 12,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : filteredGroups.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            key: const ValueKey('dedupe-groups-list'),
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(28, 12, 28, 48),
                            itemCount: filteredGroups.length,
                            separatorBuilder: (context, _) => const SizedBox(height: 24),
                            itemBuilder: (context, index) {
                              final group = filteredGroups[index];
                              return _buildGroupCard(group);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回媒体库',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.libraryName != null
                    ? '媒体库查重与智能去重 · ${widget.libraryName}'
                    : '媒体库查重与智能去重',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                '基于 TMDb 元数据、封面海报、同名演职员、片长及识别码，多维聚类识别冗余文件',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _scanning ? null : _initAndScan,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重新扫描'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBar(int groupCount, String formattedSavings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 14),
      child: Row(
        children: [
          _buildMetricCard(
            title: '已扫描条目',
            value: '$_scannedItemCount 项',
            icon: Icons.movie_filter_outlined,
            color: AppColors.indigo,
          ),
          const SizedBox(width: 14),
          _buildMetricCard(
            title: '发现重复组',
            value: '$groupCount 组',
            icon: Icons.difference_rounded,
            color: AppColors.spotlight,
          ),
          const SizedBox(width: 14),
          _buildMetricCard(
            title: '预估可释放空间',
            value: formattedSavings,
            icon: Icons.cleaning_services_rounded,
            color: AppColors.success,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: AppGlass.decoration(radius: 16, elevated: true),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
      child: Row(
        children: [
          _filterChip('all', '全部类型'),
          const SizedBox(width: 8),
          _filterChip('movie', '电影'),
          const SizedBox(width: 8),
          _filterChip('series', '剧集/单集'),
          const SizedBox(width: 8),
          _filterChip('local', '本地文件'),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _selectedFilter == key;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selectedFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.spotlight.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.spotlight
                : Colors.white.withValues(alpha: 0.15),
            width: 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.spotlight : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard(DuplicateMediaGroup group) {
    return Container(
      decoration: AppGlass.decoration(radius: 20, elevated: true),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.copy_all_rounded, size: 20, color: AppColors.spotlight),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      group.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (group.productionYear != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(${group.productionYear})',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              VisionGlassBadge(
                label: group.matchDetail,
                icon: Icons.verified_outlined,
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: () => _ignoreGroup(group),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 16),
                label: const Text('忽略此组'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 16),
          // Items row comparison
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final groupItem in group.items)
                _buildItemComparisonCard(group, groupItem),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemComparisonCard(
    DuplicateMediaGroup group,
    DuplicateGroupItem groupItem,
  ) {
    final item = groupItem.item;
    final metrics = groupItem.metrics;
    final isKeep = groupItem.isRecommendedKeep;
    final isSelectedDelete = group.selectedDeleteIds.contains(item.id);

    return Container(
      width: 380,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isKeep
            ? AppColors.success.withValues(alpha: 0.08)
            : (isSelectedDelete
                ? AppColors.error.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isKeep
              ? AppColors.success.withValues(alpha: 0.45)
              : (isSelectedDelete
                  ? AppColors.error.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.12)),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster
          SizedBox(
            width: 72,
            height: 108,
            child: Peek3DCard(
              onTap: () => _openDetail(item),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: PeekMediaImage(
                  uri: item.imageUri,
                  headers: item.imageHeaders,
                  kind: PeekMediaImageKind.poster,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isKeep)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '推荐保留 (优质)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '冗余拷贝',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      '综合评分: ${metrics.qualityScore}',
                      style: const TextStyle(
                        fontFamily: 'Cascadia Mono',
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    VisionGlassBadge(
                      label: metrics.resolutionLabel,
                      icon: Icons.hd_rounded,
                    ),
                    VisionGlassBadge(
                      label: metrics.videoCodec,
                      icon: Icons.video_file_outlined,
                    ),
                    VisionGlassBadge(
                      label: metrics.formattedFileSize,
                      icon: Icons.storage_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (metrics.advantageTags.isNotEmpty)
                  Text(
                    '亮点: ${metrics.advantageTags.join(" · ")}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                const SizedBox(height: 10),
                // Actions
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: () => _openPreviewPlayback(item),
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: const Text('试播对比', style: TextStyle(fontSize: 11)),
                    ),
                    const Spacer(),
                    if (!isKeep) ...[
                      InkWell(
                        onTap: () => _toggleDeleteSelection(group.id, item.id),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: isSelectedDelete,
                              onChanged: (_) => _toggleDeleteSelection(group.id, item.id),
                            ),
                            const Text('标记', style: TextStyle(fontSize: 11)),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error.withValues(alpha: 0.85),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: const Size(0, 32),
                        ),
                        onPressed: () => _deleteItem(item),
                        icon: const Icon(Icons.delete_outline_rounded, size: 14),
                        label: const Text('清理删除', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: AppGlass.decoration(radius: 20),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.success,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(
              '太棒了！媒体库未发现任何冗余重复内容',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '当前分类下没有相同 TMDb ID 或同名上映年份的重复媒体。',
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
