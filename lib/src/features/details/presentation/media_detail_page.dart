import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/domain/playback_queue.dart';
import 'package:embyplayer/src/features/player/presentation/playback_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MediaDetailPage extends ConsumerStatefulWidget {
  const MediaDetailPage({
    super.key,
    required this.account,
    required this.initialItem,
  });

  final AuthenticatedServer account;
  final MediaItem initialItem;

  @override
  ConsumerState<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends ConsumerState<MediaDetailPage> {
  late MediaItem _item = widget.initialItem;
  List<MediaItem> _similarItems = const [];
  bool _loadingDetails = true;
  bool _planningPlayback = false;
  String? _detailError;
  String? _similarError;
  String? _playbackError;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadDetails);
  }

  Future<void> _loadDetails({bool forceRefresh = false}) async {
    setState(() {
      _loadingDetails = true;
      _detailError = null;
      _similarError = null;
    });
    final service = ref.read(mediaLibraryProvider);
    final detailRequest = service.getItem(
      widget.account,
      widget.initialItem.id,
      forceRefresh: forceRefresh,
    );
    final similarRequest = service.getSimilar(
      widget.account,
      widget.initialItem.id,
      forceRefresh: forceRefresh,
    );
    try {
      final item = await detailRequest;
      if (mounted) setState(() => _item = item);
    } on MediaLibraryException catch (error) {
      if (mounted) setState(() => _detailError = error.message);
    }
    try {
      final similar = await similarRequest;
      if (mounted) setState(() => _similarItems = similar);
    } on MediaLibraryException catch (error) {
      if (mounted) setState(() => _similarError = error.message);
    }
    if (mounted) setState(() => _loadingDetails = false);
  }

  Future<void> _play({bool fromBeginning = false}) async {
    setState(() {
      _planningPlayback = true;
      _playbackError = null;
    });
    final item = _item;
    final queueFuture = _buildPlaybackQueue(item);
    try {
      final plan = await ref
          .read(playbackServiceProvider)
          .createPlan(
            widget.account,
            item,
            startPosition: fromBeginning ? Duration.zero : null,
          );
      final queue = await queueFuture;
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => PlaybackPage(
            account: widget.account,
            item: item,
            plan: plan,
            queue: queue,
          ),
        ),
      );
      if (mounted) await _loadDetails(forceRefresh: true);
    } on PlaybackServiceException catch (error) {
      if (mounted) setState(() => _playbackError = error.message);
    } finally {
      if (mounted) setState(() => _planningPlayback = false);
    }
  }

  Future<PlaybackQueue?> _buildPlaybackQueue(MediaItem item) async {
    final seriesId = item.seriesId;
    if (item.kind != MediaItemKind.episode ||
        seriesId == null ||
        seriesId.isEmpty) {
      return null;
    }
    try {
      final episodes = await ref
          .read(mediaLibraryProvider)
          .getEpisodesForSeries(widget.account, seriesId: seriesId);
      return PlaybackQueue.fromEpisodes(current: item, episodes: episodes);
    } on MediaLibraryException {
      return null;
    }
  }

  bool get _playable =>
      _item.kind == MediaItemKind.movie ||
      _item.kind == MediaItemKind.episode ||
      _item.kind == MediaItemKind.video;

  Future<void> _openSimilar(MediaItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            MediaDetailPage(account: widget.account, initialItem: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackdrop(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.glassStrong.withValues(alpha: 0.9),
              surfaceTintColor: Colors.transparent,
              title: Text(
                _item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SliverToBoxAdapter(
              child: _DetailHero(
                item: _item,
                loading: _loadingDetails,
                playable: _playable,
                planningPlayback: _planningPlayback,
                onPlay: () => _play(),
                onPlayFromBeginning: () => _play(fromBeginning: true),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_detailError != null)
                          _DetailNotice(
                            message: _detailError!,
                            actionLabel: '重新读取',
                            onAction: _loadDetails,
                          ),
                        if (_playbackError != null)
                          _DetailNotice(
                            message: _playbackError!,
                            actionLabel: '重试播放',
                            onAction: _play,
                            error: true,
                          ),
                        if (_detailError != null || _playbackError != null)
                          const SizedBox(height: 18),
                        _OverviewSection(item: _item),
                        if (_item.people.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          _CastSection(people: _item.people),
                        ],
                        if (_similarItems.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          _SimilarSection(
                            items: _similarItems,
                            onOpen: _openSimilar,
                          ),
                        ] else if (_similarError != null) ...[
                          const SizedBox(height: 18),
                          _DetailNotice(
                            message: '相似推荐暂时无法读取：$_similarError',
                            actionLabel: '重试',
                            onAction: _loadDetails,
                          ),
                        ],
                      ],
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

class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.item,
    required this.loading,
    required this.playable,
    required this.planningPlayback,
    required this.onPlay,
    required this.onPlayFromBeginning,
  });

  final MediaItem item;
  final bool loading;
  final bool playable;
  final bool planningPlayback;
  final VoidCallback onPlay;
  final VoidCallback onPlayFromBeginning;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _Backdrop(item: item)),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.canvas.withValues(alpha: 0.15),
                  AppColors.canvas.withValues(alpha: 0.96),
                ],
                stops: const [0, 0.82],
              ),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final poster = _DetailPoster(item: item);
                final copy = _DetailCopy(
                  item: item,
                  playable: playable,
                  planningPlayback: planningPlayback,
                  onPlay: onPlay,
                  onPlayFromBeginning: onPlayFromBeginning,
                );
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 24 : 32,
                    compact ? 28 : 64,
                    compact ? 24 : 32,
                    52,
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(width: 180, child: poster),
                            ),
                            const SizedBox(height: 24),
                            copy,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SizedBox(width: 250, child: poster),
                            const SizedBox(width: 42),
                            Expanded(child: copy),
                          ],
                        ),
                );
              },
            ),
          ),
        ),
        if (loading)
          const Positioned(
            top: 18,
            right: 24,
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final uri = item.backdropUri ?? item.imageUri;
    if (uri == null) return const ColoredBox(color: AppColors.surfaceLow);
    return Opacity(
      opacity: 0.42,
      child: Image.network(
        uri.toString(),
        headers: item.imageHeaders,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const ColoredBox(color: AppColors.surfaceLow),
      ),
    );
  }
}

class _DetailPoster extends StatelessWidget {
  const _DetailPoster({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: AppGlass.decoration(radius: 18, elevated: true),
        child: item.imageUri == null
            ? const Icon(
                Icons.movie_outlined,
                size: 54,
                color: AppColors.textTertiary,
              )
            : Image.network(
                item.imageUri.toString(),
                headers: item.imageHeaders,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.movie_outlined,
                  size: 54,
                  color: AppColors.textTertiary,
                ),
              ),
      ),
    );
  }
}

class _DetailCopy extends StatelessWidget {
  const _DetailCopy({
    required this.item,
    required this.playable,
    required this.planningPlayback,
    required this.onPlay,
    required this.onPlayFromBeginning,
  });

  final MediaItem item;
  final bool playable;
  final bool planningPlayback;
  final VoidCallback onPlay;
  final VoidCallback onPlayFromBeginning;

  @override
  Widget build(BuildContext context) {
    final resume = item.resumePosition > Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _kindLabel(item.kind),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 10),
        Text(
          item.name,
          style: Theme.of(
            context,
          ).textTheme.displayLarge?.copyWith(fontSize: 44),
        ),
        if (item.tagline != null) ...[
          const SizedBox(height: 10),
          Text(
            item.tagline!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _metadata(
            item,
          ).map((label) => _MetadataChip(label: label)).toList(),
        ),
        if (playable) ...[
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: planningPlayback ? null : onPlay,
                icon: planningPlayback
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  planningPlayback
                      ? '正在准备播放'
                      : resume
                      ? '继续播放 · ${_position(item.resumePosition)}'
                      : '立即播放',
                ),
              ),
              if (resume)
                OutlinedButton.icon(
                  onPressed: planningPlayback ? null : onPlayFromBeginning,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('从头播放'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  List<String> _metadata(MediaItem item) {
    return [
      if (item.productionYear != null) '${item.productionYear}',
      if (item.runTime != null && item.runTime!.inMinutes > 0)
        '${item.runTime!.inMinutes} 分钟',
      if (item.officialRating != null) item.officialRating!,
      if (item.communityRating != null)
        '★ ${item.communityRating!.toStringAsFixed(1)}',
      ...item.genres.take(3),
    ];
  }

  String _position(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    return hours > 0 ? '$hours 小时 $minutes 分' : '$minutes 分钟';
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: AppGlass.decoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('剧情简介', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            item.overview ?? '服务器暂未提供简介。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _CastSection extends StatelessWidget {
  const _CastSection({required this.people});

  final List<MediaPerson> people;

  @override
  Widget build(BuildContext context) {
    final actors = people
        .where((person) {
          final type = person.type.toLowerCase();
          return type == 'actor' || type == 'gueststar';
        })
        .take(18)
        .toList();
    final visiblePeople = actors.isEmpty ? people.take(18).toList() : actors;
    if (visiblePeople.isEmpty) return const SizedBox.shrink();
    return _DetailPanel(
      eyebrow: 'CAST',
      title: '演员阵容',
      child: Wrap(
        spacing: 14,
        runSpacing: 18,
        children: [
          for (final person in visiblePeople) _PersonCard(person: person),
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});

  final MediaPerson person;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(13),
              ),
              child: person.imageUri == null
                  ? const Icon(
                      Icons.person_outline_rounded,
                      size: 38,
                      color: AppColors.textTertiary,
                    )
                  : Image.network(
                      person.imageUri.toString(),
                      headers: person.imageHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.person_outline_rounded,
                        size: 38,
                        color: AppColors.textTertiary,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            person.role ?? _personTypeLabel(person.type),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  String _personTypeLabel(String value) {
    return switch (value.toLowerCase()) {
      'actor' => '演员',
      'gueststar' => '客串',
      'director' => '导演',
      'writer' => '编剧',
      'producer' => '制片人',
      _ => value,
    };
  }
}

class _SimilarSection extends StatelessWidget {
  const _SimilarSection({required this.items, required this.onOpen});

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return _DetailPanel(
      eyebrow: 'MORE LIKE THIS',
      title: '相似推荐',
      child: Wrap(
        spacing: 14,
        runSpacing: 20,
        children: [
          for (final item in items)
            _SimilarCard(item: item, onOpen: () => onOpen(item)),
        ],
      ),
    );
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: item.imageUri == null
                        ? const Icon(
                            Icons.movie_outlined,
                            color: AppColors.textTertiary,
                          )
                        : Image.network(
                            item.imageUri.toString(),
                            headers: item.imageHeaders,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.movie_outlined,
                              color: AppColors.textTertiary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.productionYear?.toString() ?? _kindLabel(item.kind),
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
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

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.eyebrow,
    required this.title,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: AppGlass.decoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _DetailNotice extends StatelessWidget {
  const _DetailNotice({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.error = false,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.glassSurface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (error ? AppColors.error : Colors.black).withValues(
              alpha: 0.12,
            ),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: error ? AppColors.error : AppColors.spotlight,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
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
    MediaItemKind.person => '人物',
    MediaItemKind.folder => '文件夹',
  };
}
