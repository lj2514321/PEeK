import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/download/data/download_manager_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';

class BatchDownloadSheet extends StatefulWidget {
  const BatchDownloadSheet({
    super.key,
    required this.item,
    this.episodes = const [],
    required this.account,
  });

  final MediaItem item;
  final List<MediaItem> episodes;
  final AuthenticatedServer? account;

  @override
  State<BatchDownloadSheet> createState() => _BatchDownloadSheetState();
}

class _BatchDownloadSheetState extends State<BatchDownloadSheet> {
  final DownloadManagerService _downloadManager = DownloadManagerService.instance;
  final Set<String> _selectedIds = {};
  bool _enqueuing = false;

  List<MediaItem> get _itemsToDisplay =>
      widget.episodes.isNotEmpty ? widget.episodes : [widget.item];

  @override
  void initState() {
    super.initState();
    // Default select all items
    for (final it in _itemsToDisplay) {
      _selectedIds.add(it.id);
    }
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_itemsToDisplay.map((e) => e.id));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedIds.clear();
    });
  }

  void _selectUnplayed() {
    setState(() {
      _selectedIds.clear();
      for (final it in _itemsToDisplay) {
        if (!it.played) {
          _selectedIds.add(it.id);
        }
      }
    });
  }

  int _calculateSelectedSize() {
    var total = 0;
    for (final it in _itemsToDisplay) {
      if (_selectedIds.contains(it.id)) {
        final fs = it.mediaSources.isNotEmpty ? it.mediaSources.first.fileSize : it.fileSize;
        if (fs != null && fs > 0) {
          total += fs;
        } else {
          total += 800 * 1024 * 1024; // fallback 800 MB per episode
        }
      }
    }
    return total;
  }

  Future<void> _startDownload() async {
    if (_selectedIds.isEmpty || widget.account == null) return;

    setState(() => _enqueuing = true);

    final baseUrl = widget.account!.server.apiBaseUri.toString().replaceAll(RegExp(r'/$'), '');
    final token = widget.account!.accessToken;
    final scheme = widget.account!.server.kind == ServerKind.emby ? 'Emby' : 'MediaBrowser';
    final deviceId = widget.account!.deviceId;
    final headers = {
      'Authorization': '$scheme Client="PEeK", Device="Windows", DeviceId="$deviceId", Version="0.1.0", Token="$token"',
      'X-Emby-Token': token,
      'X-MediaBrowser-Token': token,
    };

    var count = 0;
    for (final it in _itemsToDisplay) {
      if (_selectedIds.contains(it.id)) {
        final streamUrl = '$baseUrl/Videos/${it.id}/stream?static=true&api_key=$token';
        final size = (it.mediaSources.isNotEmpty ? it.mediaSources.first.fileSize : it.fileSize) ?? 0;
        await _downloadManager.enqueueTask(
          itemId: it.id,
          title: it.name,
          seriesName: it.seriesName ?? widget.item.name,
          seasonNumber: it.parentIndexNumber,
          episodeNumber: it.indexNumber,
          url: streamUrl,
          estimatedBytes: size,
          headers: headers,
        );
        count++;
      }
    }

    if (mounted) {
      Navigator.of(context).pop(count);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSeries = widget.episodes.isNotEmpty;
    final totalBytes = _calculateSelectedSize();

    return Container(
      width: 580,
      constraints: const BoxConstraints(maxHeight: 640),
      padding: const EdgeInsets.all(24),
      decoration: AppGlass.decoration(radius: 24, elevated: true),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.spotlight.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.downloading_rounded,
                  color: AppColors.spotlight,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSeries ? '批量下载：${widget.item.name}' : '离线缓存：${widget.item.name}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '下载完成后自动支持离线无网本地播放',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 20,
              ),
            ],
          ),
          if (isSeries) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: _selectAll,
                  child: const Text('全选', style: TextStyle(color: AppColors.spotlight, fontSize: 12)),
                ),
                TextButton(
                  onPressed: _deselectAll,
                  child: const Text('清空', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                TextButton(
                  onPressed: _selectUnplayed,
                  child: const Text('仅未看集', style: TextStyle(color: AppColors.cyan, fontSize: 12)),
                ),
                const Spacer(),
                Text(
                  '已选 ${_selectedIds.length} / ${_itemsToDisplay.length} 集',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: PeekSmoothScroll(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _itemsToDisplay.length,
                  separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final it = _itemsToDisplay[index];
                    final isSelected = _selectedIds.contains(it.id);
                    final size = (it.mediaSources.isNotEmpty ? it.mediaSources.first.fileSize : it.fileSize) ?? 0;
                    final sizeStr = size > 0 ? DownloadTaskItem.formatBytes(size) : '约 800 MB';

                    return CheckboxListTile(
                      value: isSelected,
                      activeColor: AppColors.spotlight,
                      checkColor: AppColors.onSpotlight,
                      title: Text(
                        it.indexNumber != null ? '第 ${it.indexNumber} 话 · ${it.name}' : it.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '$sizeStr${it.played ? ' · 已看' : ''}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                      ),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedIds.add(it.id);
                          } else {
                            _selectedIds.remove(it.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '预计下载体积',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DownloadTaskItem.formatBytes(totalBytes),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.spotlight,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.spotlight,
                  foregroundColor: AppColors.onSpotlight,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _selectedIds.isEmpty || _enqueuing ? null : _startDownload,
                child: _enqueuing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Text(
                        '加入下载队列 (${_selectedIds.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
