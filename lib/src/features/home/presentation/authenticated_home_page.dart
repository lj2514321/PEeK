import 'dart:async';

import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:embyplayer/src/features/home/domain/home_feed.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/presentation/playback_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthenticatedHomePage extends ConsumerStatefulWidget {
  const AuthenticatedHomePage({
    super.key,
    required this.account,
    required this.onOpenLibrary,
    required this.onSessionExpired,
  });

  final AuthenticatedServer account;
  final VoidCallback onOpenLibrary;
  final Future<void> Function() onSessionExpired;

  @override
  ConsumerState<AuthenticatedHomePage> createState() =>
      _AuthenticatedHomePageState();
}

class _AuthenticatedHomePageState extends ConsumerState<AuthenticatedHomePage> {
  HomeFeed? _feed;
  bool _loading = true;
  bool _refreshing = false;
  String? _pageError;
  String? _planningItemId;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant AuthenticatedHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.userId != widget.account.userId ||
        oldWidget.account.server.serverId != widget.account.server.serverId) {
      _feed = null;
      Future<void>.microtask(_load);
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _loading = _feed == null;
      _pageError = null;
    });
    try {
      final feed = await ref
          .read(homeFeedProvider)
          .load(widget.account, forceRefresh: forceRefresh);
      if (mounted) setState(() => _feed = feed);
    } on MediaLibraryException catch (error) {
      if (error.authenticationExpired) {
        await widget.onSessionExpired();
      } else if (mounted) {
        setState(() => _pageError = error.message);
      }
    } on Object {
      if (mounted) {
        setState(() => _pageError = '首页内容暂时无法读取，请检查服务器连接。');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _openDetails(MediaItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            MediaDetailPage(account: widget.account, initialItem: item),
      ),
    );
    if (mounted) await _load(forceRefresh: true);
  }

  Future<void> _continuePlayback(MediaItem item) async {
    if (_planningItemId != null) return;
    setState(() => _planningItemId = item.id);
    try {
      final prepared = await ref
          .read(playbackPreparationProvider)
          .prepare(widget.account, item);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => PlaybackPage(
            account: widget.account,
            item: prepared.item,
            plan: prepared.plan,
            queue: prepared.queue,
          ),
        ),
      );
      if (mounted) await _load(forceRefresh: true);
    } on PlaybackServiceException catch (error) {
      if (mounted) _showPlaybackError(error.message);
    } on Object catch (error) {
      if (mounted) _showPlaybackError('$error');
    } finally {
      if (mounted) setState(() => _planningItemId = null);
    }
  }

  void _showPlaybackError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('无法开始播放：$message')));
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final horizontalPadding = compact ? 20.0 : 32.0;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  compact ? 22 : 30,
                  horizontalPadding,
                  12,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: _HomeHeading(
                        account: widget.account,
                        refreshing: _refreshing,
                        onRefresh: () => unawaited(_load(forceRefresh: true)),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: _loading && feed == null
                          ? const _HomeHeroSkeleton()
                          : feed?.heroItems.isNotEmpty ?? false
                          ? _HomeHeroCarousel(
                              items: feed!.heroItems,
                              dailyRecommendations:
                                  feed.dailyRecommendations.items.isNotEmpty,
                              planningItemId: _planningItemId,
                              onPlay: (item) =>
                                  unawaited(_continuePlayback(item)),
                              onDetails: (item) =>
                                  unawaited(_openDetails(item)),
                            )
                          : _HomeEmptyHero(
                              error: _pageError,
                              onOpenLibrary: widget.onOpenLibrary,
                              onRetry: () =>
                                  unawaited(_load(forceRefresh: true)),
                            ),
                    ),
                  ),
                ),
              ),
              if (_pageError != null && feed?.heroItem != null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    14,
                    horizontalPadding,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
                        child: _HomeSectionNotice(
                          message: _pageError!,
                          onRetry: () => unawaited(_load(forceRefresh: true)),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_loading && feed == null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    48,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
                        child: const _HomeTracksSkeleton(),
                      ),
                    ),
                  ),
                )
              else if (feed != null)
                ..._feedSlivers(
                  feed,
                  horizontalPadding: horizontalPadding,
                  compact: compact,
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _feedSlivers(
    HomeFeed feed, {
    required double horizontalPadding,
    required bool compact,
  }) {
    return [
      if (feed.continueWatching.items.length > 1 ||
          feed.continueWatching.hasError)
        _sectionSliver(
          title: '继续观看',
          eyebrow: 'PICK UP WHERE YOU LEFT OFF',
          section: feed.continueWatching,
          portrait: false,
          horizontalPadding: horizontalPadding,
          compact: compact,
        ),
      if (!feed.latestMovies.isEmpty || feed.latestMovies.hasError)
        _sectionSliver(
          title: '最近添加的电影',
          eyebrow: 'NEW IN YOUR LIBRARY',
          section: feed.latestMovies,
          portrait: true,
          horizontalPadding: horizontalPadding,
          compact: compact,
        ),
      if (!feed.latestEpisodes.isEmpty || feed.latestEpisodes.hasError)
        _sectionSliver(
          title: '最新剧集',
          eyebrow: 'FRESH EPISODES',
          section: feed.latestEpisodes,
          portrait: false,
          horizontalPadding: horizontalPadding,
          compact: compact,
        ),
    ];
  }

  Widget _sectionSliver({
    required String title,
    required String eyebrow,
    required HomeFeedSection section,
    required bool portrait,
    required double horizontalPadding,
    required bool compact,
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        compact ? 26 : 34,
        horizontalPadding,
        0,
      ),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: section.items.isEmpty
                ? _HomeSectionNotice(
                    title: title,
                    message: section.error ?? '这里暂时没有内容。',
                    onRetry: () => unawaited(_load(forceRefresh: true)),
                  )
                : _MediaTrack(
                    title: title,
                    eyebrow: eyebrow,
                    items: section.items,
                    portrait: portrait,
                    compact: compact,
                    onOpen: (item) => unawaited(_openDetails(item)),
                    onOpenLibrary: widget.onOpenLibrary,
                  ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeading extends StatelessWidget {
  const _HomeHeading({
    required this.account,
    required this.refreshing,
    required this.onRefresh,
  });

  final AuthenticatedServer account;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 6
        ? '夜深了'
        : hour < 12
        ? '早上好'
        : hour < 18
        ? '下午好'
        : '晚上好';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting，${account.userName}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                account.server.name,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 10,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('home-refresh'),
          tooltip: '刷新首页',
          onPressed: refreshing ? null : onRefresh,
          icon: refreshing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _HomeHeroCarousel extends StatefulWidget {
  const _HomeHeroCarousel({
    required this.items,
    required this.dailyRecommendations,
    required this.planningItemId,
    required this.onPlay,
    required this.onDetails,
  });

  final List<MediaItem> items;
  final bool dailyRecommendations;
  final String? planningItemId;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onDetails;

  @override
  State<_HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<_HomeHeroCarousel> {
  static const _autoAdvanceInterval = Duration(seconds: 5);

  final _controller = PageController();
  Timer? _timer;
  int _currentIndex = 0;
  bool _hovering = false;
  bool _disableAnimations = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations != disabled) {
      _disableAnimations = disabled;
      _scheduleNext();
    } else if (_timer == null) {
      _scheduleNext();
    }
  }

  @override
  void didUpdateWidget(covariant _HomeHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.items.map((item) => item.id).join('|');
    final nextIds = widget.items.map((item) => item.id).join('|');
    if (oldIds != nextIds) {
      _currentIndex = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
    _scheduleNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = null;
    if (_disableAnimations || _hovering || widget.items.length < 2) return;
    _timer = Timer(_autoAdvanceInterval, () => _move(1));
  }

  Future<void> _move(int direction) async {
    if (widget.items.length < 2 || !_controller.hasClients) return;
    final next = (_currentIndex + direction) % widget.items.length;
    final normalized = next < 0 ? widget.items.length - 1 : next;
    if (_disableAnimations) {
      _controller.jumpToPage(normalized);
    } else {
      await _controller.animateToPage(
        normalized,
        duration: AppMotion.standard,
        curve: Curves.easeOutCubic,
      );
    }
    _scheduleNext();
  }

  void _pageChanged(int index) {
    setState(() => _currentIndex = index);
    _scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return MouseRegion(
          onEnter: (_) {
            _hovering = true;
            _timer?.cancel();
          },
          onExit: (_) {
            _hovering = false;
            _scheduleNext();
          },
          child: SizedBox(
            key: const ValueKey('home-hero'),
            height: compact ? 410 : 430,
            child: Stack(
              children: [
                PageView.builder(
                  key: const ValueKey('daily-recommendation-carousel'),
                  controller: _controller,
                  allowImplicitScrolling: true,
                  itemCount: widget.items.length,
                  onPageChanged: _pageChanged,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return _HomeHero(
                      key: ValueKey('hero-slide-${item.id}'),
                      item: item,
                      dailyRecommendation: widget.dailyRecommendations,
                      planning: widget.planningItemId == item.id,
                      onPlay: () => widget.onPlay(item),
                      onDetails: () => widget.onDetails(item),
                    );
                  },
                ),
                if (widget.items.length > 1)
                  Positioned(
                    top: compact ? 14 : 20,
                    right: compact ? 14 : 20,
                    child: _CarouselControls(
                      currentIndex: _currentIndex,
                      itemCount: widget.items.length,
                      onPrevious: () => unawaited(_move(-1)),
                      onNext: () => unawaited(_move(1)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CarouselControls extends StatelessWidget {
  const _CarouselControls({
    required this.currentIndex,
    required this.itemCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentIndex;
  final int itemCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('hero-previous'),
            tooltip: '上一条推荐',
            visualDensity: VisualDensity.compact,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
          ),
          Semantics(
            liveRegion: true,
            label: '第 ${currentIndex + 1} 条，共 $itemCount 条每日推荐',
            child: Text(
              '${(currentIndex + 1).toString().padLeft(2, '0')} / '
              '${itemCount.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cascadia Mono',
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('hero-next'),
            tooltip: '下一条推荐',
            visualDensity: VisualDensity.compact,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    super.key,
    required this.item,
    required this.dailyRecommendation,
    required this.planning,
    required this.onPlay,
    required this.onDetails,
  });

  final MediaItem item;
  final bool dailyRecommendation;
  final bool planning;
  final VoidCallback onPlay;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final resumable = item.resumePosition > Duration.zero;
    final progress = item.runTime == null || item.runTime == Duration.zero
        ? 0.0
        : (item.resumePosition.inMilliseconds / item.runTime!.inMilliseconds)
              .clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return Container(
          height: compact ? 410 : 430,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceLow,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _HeroArtwork(item: item),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: compact
                        ? Alignment.topCenter
                        : Alignment.centerRight,
                    end: compact
                        ? Alignment.bottomCenter
                        : Alignment.centerLeft,
                    colors: compact
                        ? const [
                            Color(0x1908090D),
                            Color(0xA608090D),
                            Color(0xFA08090D),
                          ]
                        : const [
                            Color(0x1908090D),
                            Color(0xB508090D),
                            Color(0xFC08090D),
                          ],
                    stops: compact
                        ? const [0, 0.48, 0.82]
                        : const [0, 0.52, 0.88],
                  ),
                ),
              ),
              Align(
                alignment: compact
                    ? Alignment.bottomLeft
                    : Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.all(compact ? 24 : 42),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 560 : 620),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dailyRecommendation
                              ? 'DAILY RECOMMENDATION'
                              : resumable
                              ? 'CONTINUE WATCHING'
                              : 'NEW IN YOUR LIBRARY',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.spotlight),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(fontSize: compact ? 34 : 48),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _itemMetadata(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (!compact && item.overview != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            item.overview!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              height: 1.55,
                            ),
                          ),
                        ],
                        if (resumable) ...[
                          const SizedBox(height: 20),
                          _ProjectionProgress(
                            value: progress,
                            position: item.resumePosition,
                            duration: item.runTime,
                          ),
                        ],
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              key: const ValueKey('home-hero-play'),
                              onPressed: planning ? null : onPlay,
                              icon: planning
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.play_arrow_rounded),
                              label: Text(resumable ? '继续播放' : '立即播放'),
                            ),
                            TextButton.icon(
                              onPressed: planning ? null : onDetails,
                              icon: const Icon(Icons.info_outline_rounded),
                              label: const Text('查看详情'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final uri = item.backdropUri ?? item.imageUri;
    if (uri == null) {
      return const ColoredBox(
        color: AppColors.surfaceLow,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 88),
            child: Icon(
              Icons.local_movies_outlined,
              size: 92,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      );
    }
    return Image.network(
      uri.toString(),
      headers: item.imageHeaders,
      fit: BoxFit.cover,
      alignment: Alignment.centerRight,
      errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceLow),
    );
  }
}

class _ProjectionProgress extends StatelessWidget {
  const _ProjectionProgress({
    required this.value,
    required this.position,
    required this.duration,
  });

  final double value;
  final Duration position;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '观看进度 ${(value * 100).round()}%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              key: const ValueKey('home-hero-progress'),
              value: value,
              minHeight: 3,
              color: AppColors.spotlight,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '看到 ${_time(position)}${duration == null ? '' : ' / ${_time(duration!)}'}',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontFamily: 'Cascadia Mono',
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTrack extends StatelessWidget {
  const _MediaTrack({
    required this.title,
    required this.eyebrow,
    required this.items,
    required this.portrait,
    required this.compact,
    required this.onOpen,
    required this.onOpenLibrary,
  });

  final String title;
  final String eyebrow;
  final List<MediaItem> items;
  final bool portrait;
  final bool compact;
  final ValueChanged<MediaItem> onOpen;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final width = portrait
        ? (compact ? 136.0 : 164.0)
        : (compact ? 238.0 : 290.0);
    final height = portrait
        ? (compact ? 258.0 : 310.0)
        : (compact ? 190.0 : 218.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 5),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            TextButton(onPressed: onOpenLibrary, child: const Text('查看媒体库')),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: height,
          child: ListView.separated(
            key: ValueKey('home-track-$title'),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) => SizedBox(
              width: width,
              child: _HomeMediaCard(
                item: items[index],
                portrait: portrait,
                onOpen: () => onOpen(items[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeMediaCard extends StatelessWidget {
  const _HomeMediaCard({
    required this.item,
    required this.portrait,
    required this.onOpen,
  });

  final MediaItem item;
  final bool portrait;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = item.runTime == null || item.runTime == Duration.zero
        ? 0.0
        : (item.resumePosition.inMilliseconds / item.runTime!.inMilliseconds)
              .clamp(0.0, 1.0);
    return Semantics(
      button: true,
      label: '${item.name}，${_kindLabel(item.kind)}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CardArtwork(item: item, portrait: portrait),
                    if (item.played)
                      const Positioned(
                        top: 9,
                        right: 9,
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                          size: 20,
                        ),
                      ),
                    if (progress > 0)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          color: AppColors.spotlight,
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                _itemMetadata(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardArtwork extends StatelessWidget {
  const _CardArtwork({required this.item, required this.portrait});

  final MediaItem item;
  final bool portrait;

  @override
  Widget build(BuildContext context) {
    final uri = portrait ? item.imageUri : item.backdropUri ?? item.imageUri;
    final fallback = ColoredBox(
      color: AppColors.surfaceLow,
      child: Icon(
        item.kind == MediaItemKind.episode
            ? Icons.live_tv_outlined
            : Icons.movie_outlined,
        color: AppColors.textTertiary,
        size: 38,
      ),
    );
    if (uri == null) return fallback;
    return Image.network(
      uri.toString(),
      headers: item.imageHeaders,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _HomeEmptyHero extends StatelessWidget {
  const _HomeEmptyHero({
    required this.error,
    required this.onOpenLibrary,
    required this.onRetry,
  });

  final String? error;
  final VoidCallback onOpenLibrary;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 310),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            error == null
                ? Icons.video_library_outlined
                : Icons.cloud_off_outlined,
            size: 42,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            error == null ? '片库已经准备好' : '首页内容暂时无法读取',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            error ?? '播放过的内容和最近添加项目会出现在这里。',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              if (error != null)
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新读取'),
                ),
              FilledButton.icon(
                onPressed: onOpenLibrary,
                icon: const Icon(Icons.video_library_rounded),
                label: const Text('打开媒体库'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeSectionNotice extends StatelessWidget {
  const _HomeSectionNotice({
    this.title,
    required this.message,
    required this.onRetry,
  });

  final String? title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.textTertiary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title == null ? message : '$title：$message',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _HomeHeroSkeleton extends StatelessWidget {
  const _HomeHeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('home-hero-loading'),
      height: 430,
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.all(36),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBar(width: 110, height: 10),
          SizedBox(height: 16),
          _SkeletonBar(width: double.infinity, height: 38),
          SizedBox(height: 14),
          _SkeletonBar(width: 220, height: 12),
          SizedBox(height: 24),
          _SkeletonBar(width: 130, height: 44),
        ],
      ),
    );
  }
}

class _HomeTracksSkeleton extends StatelessWidget {
  const _HomeTracksSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SkeletonBar(width: 180, height: 22),
        const SizedBox(height: 16),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, _) => Container(
              width: 260,
              decoration: BoxDecoration(
                color: AppColors.surfaceLow,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

String _itemMetadata(MediaItem item) {
  final values = <String>[
    if (item.seriesName != null) item.seriesName!,
    if (item.parentIndexNumber != null || item.indexNumber != null)
      'S${(item.parentIndexNumber ?? 0).toString().padLeft(2, '0')}'
          'E${(item.indexNumber ?? 0).toString().padLeft(2, '0')}',
    if (item.productionYear != null) '${item.productionYear}',
    if (item.runTime != null && item.runTime!.inMinutes > 0)
      '${item.runTime!.inMinutes} 分钟',
    if (item.seriesName == null) _kindLabel(item.kind),
  ];
  return values.join(' · ');
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

String _time(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours > 0) return '$hours 小时 $minutes 分';
  return '$minutes 分钟';
}
