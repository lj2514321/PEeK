import 'package:embyplayer/src/app/app_routes.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/download/data/download_manager_service.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter/material.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({
    super.key,
    this.downloadManager,
    this.onPlayDownloadedItem,
  });

  final DownloadManagerService? downloadManager;
  final ValueChanged<DownloadTaskItem>? onPlayDownloadedItem;

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage>
    with SingleTickerProviderStateMixin {
  late final DownloadManagerService _manager =
      widget.downloadManager ?? DownloadManagerService.instance;
  late final TabController _tabController;
  final _downloadingController = SmoothScrollController();
  final _completedController = SmoothScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _manager.init();
  }

  @override
  void dispose() {
    _downloadingController.dispose();
    _completedController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _playTask(DownloadTaskItem task) {
    if (widget.onPlayDownloadedItem != null) {
      widget.onPlayDownloadedItem!(task);
      return;
    }

    final localItem = MediaItem(
      id: task.itemId,
      name: task.displayTitle,
      kind: MediaItemKind.video,
      seriesName: task.seriesName,
      parentIndexNumber: task.seasonNumber,
      indexNumber: task.episodeNumber,
      source: MediaItemSource.local,
      sourcePath: task.savePath,
    );

    final plan = PlaybackPlan(
      itemId: task.itemId,
      mediaSourceId: task.mediaSourceId ?? 'local',
      playSessionId: 'offline-${DateTime.now().microsecondsSinceEpoch}',
      streamUri: Uri.file(task.savePath),
      method: PlaybackMethod.directPlay,
    );

    AppRoutes.openPlayback(
      context,
      account: null,
      item: localItem,
      plan: plan,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<DownloadTaskItem>>(
      valueListenable: _manager.tasksNotifier,
      builder: (context, tasks, _) {
        final downloadingTasks = tasks
            .where((t) => t.status != DownloadTaskStatus.completed)
            .toList(growable: false);
        final completedTasks = tasks
            .where((t) => t.status == DownloadTaskStatus.completed)
            .toList(growable: false);

        final totalCompletedBytes = completedTasks.fold<int>(
          0,
          (sum, t) => sum + (t.downloadedBytes > 0 ? t.downloadedBytes : t.totalBytes),
        );

        final totalSpeed = downloadingTasks
            .where((t) => t.status == DownloadTaskStatus.downloading)
            .fold<double>(0.0, (sum, t) => sum + t.speedBytesPerSec);

        final speedFormatted = totalSpeed > 0
            ? DownloadTaskItem(
                id: '',
                itemId: '',
                title: '',
                url: '',
                savePath: '',
                createdAt: DateTime.now(),
                speedBytesPerSec: totalSpeed,
              ).formattedSpeed
            : '';

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(
                  downloadingCount: downloadingTasks.length,
                  completedCount: completedTasks.length,
                  totalCompletedBytes: totalCompletedBytes,
                  speedFormatted: speedFormatted,
                ),
                const SizedBox(height: 20),
                _buildTabBar(
                  downloadingCount: downloadingTasks.length,
                  completedCount: completedTasks.length,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDownloadingTab(downloadingTasks),
                      _buildCompletedTab(completedTasks),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader({
    required int downloadingCount,
    required int completedCount,
    required int totalCompletedBytes,
    required String speedFormatted,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.spotlight.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.downloading_rounded,
            color: AppColors.spotlight,
            size: 26,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '离线下载中心',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (speedFormatted.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.arrow_downward_rounded,
                            size: 14,
                            color: AppColors.cyan,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            speedFormatted,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '已缓存离线空间：${DownloadTaskItem.formatBytes(totalCompletedBytes)} · 无网环境直读本地文件流',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
        if (downloadingCount > 0) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.pause_rounded, size: 16),
            label: const Text('全部暂停'),
            onPressed: () => _manager.pauseAll(),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.spotlight,
              foregroundColor: AppColors.onSpotlight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('全部开始'),
            onPressed: () => _manager.resumeAll(),
          ),
        ],
      ],
    );
  }

  Widget _buildTabBar({
    required int downloadingCount,
    required int completedCount,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.spotlight.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.spotlight.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AppColors.spotlight,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: [
          Tab(
            text: downloadingCount > 0
                ? '传输中 ($downloadingCount)'
                : '传输中',
          ),
          Tab(
            text: completedCount > 0
                ? '已完成 ($completedCount)'
                : '已完成',
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadingTab(List<DownloadTaskItem> tasks) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_done_rounded,
              size: 56,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            const Text(
              '没有正在进行的下载任务',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              '在电影或电视剧详情页点击「缓存下载」即可加入队列',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: _downloadingController,
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildDownloadingTaskCard(task);
      },
    );
  }

  Widget _buildDownloadingTaskCard(DownloadTaskItem task) {
    Color statusColor = AppColors.spotlight;
    IconData statusIcon = Icons.downloading_rounded;
    if (task.status == DownloadTaskStatus.paused) {
      statusColor = AppColors.textTertiary;
      statusIcon = Icons.pause_circle_outline_rounded;
    } else if (task.status == DownloadTaskStatus.failed) {
      statusColor = AppColors.error;
      statusIcon = Icons.error_outline_rounded;
    } else if (task.status == DownloadTaskStatus.queued) {
      statusColor = AppColors.cyan;
      statusIcon = Icons.schedule_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.displayTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.status.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (task.status == DownloadTaskStatus.downloading)
                IconButton(
                  tooltip: '暂停',
                  icon: const Icon(Icons.pause_rounded, color: Colors.white70, size: 20),
                  onPressed: () => _manager.pauseTask(task.id),
                  splashRadius: 18,
                )
              else
                IconButton(
                  tooltip: '继续',
                  icon: const Icon(Icons.play_arrow_rounded, color: AppColors.spotlight, size: 20),
                  onPressed: () => _manager.resumeTask(task.id),
                  splashRadius: 18,
                ),
              IconButton(
                tooltip: '取消并删除任务',
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54, size: 20),
                onPressed: () => _manager.deleteTask(task.id),
                splashRadius: 18,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.totalBytes > 0 ? task.progress : null,
              backgroundColor: Colors.white10,
              color: statusColor,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${DownloadTaskItem.formatBytes(task.downloadedBytes)} / ${DownloadTaskItem.formatBytes(task.totalBytes)} (${(task.progress * 100).toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const Spacer(),
              if (task.isDownloading)
                Text(
                  task.formattedSpeed,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cyan,
                  ),
                )
              else if (task.errorMessage != null)
                Text(
                  task.errorMessage!,
                  style: const TextStyle(fontSize: 11, color: AppColors.error),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedTab(List<DownloadTaskItem> tasks) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 56,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            const Text(
              '暂无已下载完成的离线媒体',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: _completedController,
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildCompletedTaskCard(task);
      },
    );
  }

  Widget _buildCompletedTaskCard(DownloadTaskItem task) {
    final size = task.downloadedBytes > 0 ? task.downloadedBytes : task.totalBytes;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.displayTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${DownloadTaskItem.formatBytes(size)} · 本地直出播放',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.spotlight,
              foregroundColor: AppColors.onSpotlight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('播放', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _playTask(task),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '删除离线文件',
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54, size: 20),
            onPressed: () => _manager.deleteTask(task.id, deleteFile: true),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}
