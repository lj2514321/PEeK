import 'dart:async';
import 'dart:ui';

import 'package:embyplayer/src/app/app_routes.dart';
import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_3d_card.dart';
import 'package:embyplayer/src/core/presentation/peek_context_menu.dart';
import 'package:embyplayer/src/core/presentation/peek_horizontal_rail.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/home/domain/home_feed.dart';
import 'package:embyplayer/src/features/player/data/external_player_service.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/presentation/global_playback_coordinator.dart';
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
    this.active = true,
    this.clock,
  });

  final AuthenticatedServer account;
  final VoidCallback onOpenLibrary;
  final Future<void> Function() onSessionExpired;
  final bool active;
  final DateTime Function()? clock;

  @override
  ConsumerState<AuthenticatedHomePage> createState() =>
      AuthenticatedHomePageState();
}

class AuthenticatedHomePageState extends ConsumerState<AuthenticatedHomePage> {
  final _scrollController = SmoothScrollController();
  HomeFeed? _feed;
  bool _loading = true;
  bool _refreshing = false;
  String? _pageError;
  String? _planningItemId;
  Timer? _dailyRecommendationTimer;
  bool _refreshingRecommendations = false;
  int _activeHeroIndex = 0;
  MediaItem? _hoveredAmbientItem;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
    _scheduleDailyRecommendationRefresh();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.userId != widget.account.userId ||
        oldWidget.account.server.serverId != widget.account.server.serverId) {
      _feed = null;
      _activeHeroIndex = 0;
      _hoveredAmbientItem = null;
      Future<void>.microtask(_load);
      _scheduleDailyRecommendationRefresh();
    }
  }

  @override
  void dispose() {
    _dailyRecommendationTimer?.cancel();
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
      if (mounted) {
        setState(() {
          _feed = feed;
          _activeHeroIndex = 0;
        });

        // Pre-cache first hero backdrop in image cache so initial entrance is stutter-free
        if (feed.dailyRecommendations.items.isNotEmpty) {
          final firstHero = feed.dailyRecommendations.items.first;
          final heroUri = firstHero.backdropUri ?? firstHero.imageUri;
          if (heroUri != null && mounted) {
            unawaited(precacheImage(
              NetworkImage(heroUri.toString(), headers: firstHero.imageHeaders),
              context,
            ));
          }
        }
      }
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

  Future<void> _refreshContinueWatching({bool force = false}) async {
    final currentFeed = _feed;
    if (currentFeed == null) {
      await _load();
      return;
    }
    if (_refreshing && !force) return;
    setState(() => _refreshing = true);
    try {
      final feed = await ref
          .read(homeFeedProvider)
          .refreshContinueWatching(widget.account, currentFeed);
      if (mounted) setState(() => _feed = feed);
    } on MediaLibraryException catch (error) {
      if (error.authenticationExpired) {
        await widget.onSessionExpired();
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  static const _recommendationRefreshInterval = Duration(hours: 24);

  void _scheduleDailyRecommendationRefresh() {
    _dailyRecommendationTimer?.cancel();
    _dailyRecommendationTimer = Timer(
      _recommendationRefreshInterval,
      () => unawaited(_runDailyRecommendationRefresh()),
    );
  }

  Future<void> _runDailyRecommendationRefresh() async {
    await _refreshDailyRecommendations();
    if (mounted) _scheduleDailyRecommendationRefresh();
  }

  Future<void> _refreshDailyRecommendations() async {
    final currentFeed = _feed;
    if (currentFeed == null || _refreshing || _refreshingRecommendations) {
      return;
    }
    _refreshingRecommendations = true;
    try {
      final feed = await ref
          .read(homeFeedProvider)
          .refreshRecommendations(widget.account, currentFeed);
      if (mounted) {
        setState(() {
          _feed = feed;
          _activeHeroIndex = 0;
        });
      }
    } on MediaLibraryException catch (error) {
      if (error.authenticationExpired) {
        await widget.onSessionExpired();
      }
    } finally {
      _refreshingRecommendations = false;
    }
  }

  Future<void> _openDetails(MediaItem item) async {
    // 1. Pre-warm artwork before transition starts to prevent GPU/main-thread decode jank
    final backdropUri = item.backdropUri ?? item.imageUri;
    if (backdropUri != null && mounted) {
      unawaited(precacheImage(
        NetworkImage(backdropUri.toString(), headers: item.imageHeaders),
        context,
      ));
    }
    if (item.imageUri != null && mounted) {
      unawaited(precacheImage(
        NetworkImage(item.imageUri.toString(), headers: item.imageHeaders),
        context,
      ));
    }

    final targetOffset = _scrollController.hasClients
        ? _scrollController.offset
        : null;
    await AppRoutes.openMediaDetail(
      context,
      account: widget.account,
      item: item,
    );
    if (!mounted) return;
    await _refreshContinueWatching();
    if (targetOffset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final maxScroll = _scrollController.position.maxScrollExtent;
        final clamped = targetOffset.clamp(0.0, maxScroll);
        if ((_scrollController.offset - clamped).abs() > 0.5) {
          _scrollController.jumpTo(clamped);
        }
      });
    }
  }

  Future<void> _continuePlayback(MediaItem item) async {
    if (_planningItemId != null) return;
    setState(() => _planningItemId = item.id);
    try {
      final coordinator = ref.read(globalPlaybackCoordinatorProvider.notifier);
      final livePos = coordinator.getEffectivePosition(item.id);
      final effectiveItem = livePos != null && livePos > item.resumePosition
          ? item.copyWith(resumePosition: livePos)
          : item;
      final prepared = await ref
          .read(playbackPreparationProvider)
          .prepare(widget.account, effectiveItem, startPosition: livePos);
      if (!mounted) return;

      if (prepared.settings.useExternalPlayer) {
        final service = ref.read(externalPlayerServiceProvider);
        final launched = await service.launch(
          prepared.plan,
          executablePath: prepared.settings.externalPlayerPath,
          title: item.name,
        );
        if (!mounted) return;
        if (launched) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已在外部播放器中启动《${item.name}》')));
          await _refreshContinueWatching();
          return;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未能唤起外部播放器，正在回退到内置播放器...')),
          );
        }
      }

      await AppRoutes.openPlayback(
        context,
        account: widget.account,
        item: prepared.item,
        plan: prepared.plan,
        queue: prepared.queue,
        hardwareDecodingMode: prepared.settings.hardwareDecodingMode,
        maxStreamingBitrate: prepared.settings.maxStreamingBitrate,
        subtitlePreferences: prepared.settings.subtitlePreferences,
        enableMiniPlayer: prepared.settings.enableMiniPlayer,
        longPressSpeed: prepared.settings.longPressSpeed,
      );
      if (mounted) await _refreshContinueWatching();
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

  MediaItem? _resolveAmbientItem(HomeFeed? feed) {
    if (_hoveredAmbientItem != null) return _hoveredAmbientItem;
    if (feed == null || feed.heroItems.isEmpty) return null;
    final safeIndex = _activeHeroIndex.clamp(0, feed.heroItems.length - 1);
    return feed.heroItems[safeIndex];
  }

  void _syncGlobalAmbient(MediaItem? item, int paletteSeed) {
    final uri = item?.backdropUri ?? item?.imageUri;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SpatialAmbientController.instance.update(
        itemId: item?.id,
        imageUri: uri,
        imageHeaders: item?.imageHeaders ?? const {},
        paletteSeed: paletteSeed,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(globalPlaybackCoordinatorProvider, (prev, next) {
      final wasActive =
          prev?.mode == PlaybackPresentationMode.mini ||
          prev?.mode == PlaybackPresentationMode.window ||
          prev?.mode == PlaybackPresentationMode.full;
      if (wasActive && next.mode == PlaybackPresentationMode.hidden) {
        unawaited(_refreshContinueWatching());
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            unawaited(_refreshContinueWatching(force: true));
          }
        });
      }
    });
    final feed = _feed;
    final ambientItem = _resolveAmbientItem(feed);
    _syncGlobalAmbient(ambientItem, _activeHeroIndex);
    final hasGlobalBackdrop = AmbientBackdropScope.hasAncestor(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fallback local backdrop only when pumped standalone outside HomeShell
        if (!hasGlobalBackdrop)
          Positioned.fill(
            child: IgnorePointer(
              child: _VisionSpatialAmbientBackdrop(
                item: ambientItem,
                paletteSeed: _activeHeroIndex,
              ),
            ),
          ),
        // Layer 1: Spatial Liquid Glass Scroll Content
        RefreshIndicator(
          onRefresh: () => _load(forceRefresh: true),
          child: Builder(
            builder: (context) {
              final compact = MediaQuery.sizeOf(context).width < 720;
              final leftPadding = compact ? 0.0 : 28.0;
              const scrollbarWidth = 16.0;
              final rightPadding = compact ? 0.0 : scrollbarWidth;
              return PeekSmoothScroll(
                controller: _scrollController,
                child: CustomScrollView(
                  key: const PageStorageKey('authenticated-home-scroll-view'),
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        leftPadding,
                        compact ? 8 : 12,
                        rightPadding,
                        10,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _HomeHeading(
                          account: widget.account,
                          refreshing: _refreshing,
                          onRefresh: () => unawaited(_load(forceRefresh: true)),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        leftPadding,
                        0,
                        rightPadding,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _loading && feed == null
                            ? const _HomeHeroSkeleton()
                            : feed?.heroItems.isNotEmpty ?? false
                            ? _HomeHeroCarousel(
                                items: feed!.heroItems,
                                continueWatchingItems:
                                    feed.continueWatching.items,
                                dailyRecommendations:
                                    feed.dailyRecommendations.items.isNotEmpty,
                                active: widget.active,
                                planningItemId: _planningItemId,
                                onActiveIndexChanged: (index) {
                                  if (_activeHeroIndex != index) {
                                    setState(() {
                                      _activeHeroIndex = index;
                                      _hoveredAmbientItem = null;
                                    });
                                  }
                                },
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
                    if (_pageError != null && feed?.heroItem != null)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          leftPadding,
                          14,
                          rightPadding,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _HomeSectionNotice(
                            message: _pageError!,
                            onRetry: () => unawaited(_load(forceRefresh: true)),
                          ),
                        ),
                      ),
                    if (_loading && feed == null)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          leftPadding,
                          24,
                          rightPadding,
                          0,
                        ),
                        sliver: const SliverToBoxAdapter(
                          child: _HomeTracksSkeleton(),
                        ),
                      )
                    else if (feed != null)
                      ..._feedSlivers(
                        feed,
                        leftPadding: leftPadding,
                        rightPadding: rightPadding,
                        compact: compact,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _feedSlivers(
    HomeFeed feed, {
    required double leftPadding,
    required double rightPadding,
    required bool compact,
  }) {
    return [
      if (feed.continueWatching.items.isNotEmpty ||
          feed.continueWatching.hasError)
        _sectionSliver(
          title: '继续观看',
          eyebrow: 'PICK UP WHERE YOU LEFT OFF',
          section: feed.continueWatching,
          portrait: false,
          leftPadding: leftPadding,
          rightPadding: rightPadding,
          compact: compact,
        ),
      for (final group in feed.latestMovies.groups)
        if (!group.section.isEmpty || group.section.hasError)
          _sectionSliver(
            title: '${group.library.name} · 最近添加',
            eyebrow: 'RECENTLY ADDED MOVIES',
            section: group.section,
            portrait: true,
            leftPadding: leftPadding,
            rightPadding: rightPadding,
            compact: compact,
            railId: 'latest-movies-${group.library.id}',
            libraryActionLabel: '全部媒体库',
          ),
      if (feed.latestMovies.groups.isEmpty && feed.latestMovies.error != null)
        _sectionSliver(
          title: '最近添加的电影',
          eyebrow: 'NEW IN YOUR LIBRARY',
          section: HomeFeedSection(error: feed.latestMovies.error),
          portrait: true,
          leftPadding: leftPadding,
          rightPadding: rightPadding,
          compact: compact,
        ),
      if (!feed.latestEpisodes.isEmpty || feed.latestEpisodes.hasError)
        _sectionSliver(
          title: '最新剧集',
          eyebrow: 'FRESH EPISODES',
          section: feed.latestEpisodes,
          portrait: false,
          leftPadding: leftPadding,
          rightPadding: rightPadding,
          compact: compact,
        ),
    ];
  }

  Widget _sectionSliver({
    required String title,
    required String eyebrow,
    required HomeFeedSection section,
    required bool portrait,
    required double leftPadding,
    required double rightPadding,
    required bool compact,
    String? railId,
    String libraryActionLabel = '查看媒体库',
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        leftPadding,
        compact ? 20 : 26,
        rightPadding,
        0,
      ),
      sliver: SliverToBoxAdapter(
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
                railId: railId ?? title,
                libraryActionLabel: libraryActionLabel,
                onOpen: (item) => unawaited(_openDetails(item)),
                onHover: (item) {
                  if (_hoveredAmbientItem?.id != item.id) {
                    setState(() => _hoveredAmbientItem = item);
                  }
                },
                onOpenLibrary: widget.onOpenLibrary,
              ),
      ),
    );
  }
}

/// VisionOS Full-Bleed Dynamic Ambient Light Backdrop.
///
/// Uses the active movie's artwork + multi-hue atmospheric color wash
/// (`暖金环境光` / `赛博紫环境光` / `深空蓝环境光`) so all foreground liquid glass
/// panels refract living movie colors.
class _VisionSpatialAmbientBackdrop extends StatelessWidget {
  const _VisionSpatialAmbientBackdrop({
    required this.item,
    required this.paletteSeed,
  });

  final MediaItem? item;
  final int paletteSeed;

  static const _ambientThemes = [
    // 0: 暖金沙漠环境光 (Warm Dune Amber)
    [Color(0xFF5C3A16), Color(0xFF2E1C10), Color(0xFF0E131F)],
    // 1: 赛博霓虹紫环境光 (Cyberpunk Violet/Magenta)
    [Color(0xFF4A1D66), Color(0xFF1A2552), Color(0xFF090D1A)],
    // 2: 深空星云蓝环境光 (Interstellar Deep Nebula Blue)
    [Color(0xFF124268), Color(0xFF1A2C4E), Color(0xFF080C16)],
  ];

  @override
  Widget build(BuildContext context) {
    final uri = item?.backdropUri ?? item?.imageUri;
    final themeIndex =
        ((item?.id.hashCode.abs() ?? paletteSeed) + paletteSeed) %
        _ambientThemes.length;
    final colors = _ambientThemes[themeIndex];

    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: AppMotion.responsive(
          context,
          const Duration(milliseconds: 650),
        ),
        child: Stack(
          key: ValueKey('ambient-${item?.id ?? 'none'}-$paletteSeed'),
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
            ),
            if (uri != null)
              Transform.scale(
                scale: 1.14,
                child: Opacity(
                  opacity: 0.58,
                  child: PeekMediaImage(
                    uri: uri,
                    headers: item?.imageHeaders ?? const {},
                    kind: PeekMediaImageKind.backdrop,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.45),
                    radius: 1.25,
                    colors: [
                      colors.first.withValues(alpha: 0.42),
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.62),
                    ],
                    stops: const [0.0, 0.55, 1.0],
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

/// VisionOS Liquid Glass Surface container with specular highlight rim.
class _VisionLiquidGlassPanel extends StatelessWidget {
  const _VisionLiquidGlassPanel({
    required this.child,
    this.radius = AppRadius.value,
    this.padding,
    this.blur = 34.0,
    this.topAlpha = 0.17,
    this.bottomAlpha = 0.06,
    this.borderAlpha = 0.34,
    this.hasBackdropBlur = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final double topAlpha;
  final double bottomAlpha;
  final double borderAlpha;
  final bool hasBackdropBlur;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: topAlpha),
            Colors.white.withValues(alpha: bottomAlpha),
          ],
        ),
        borderRadius: borderRadius,
        border: Border.all(
          color: Colors.white.withValues(alpha: borderAlpha),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 42,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.06),
            blurRadius: 1,
            spreadRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            if (hasBackdropBlur && blur > 0)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: const SizedBox.expand(),
                ),
              ),
            Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showBadge = constraints.maxWidth >= 620;
          return Row(
            children: [
              if (showBadge) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: AppRadius.borderRadius,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.34),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'VisionOS Spatial Cinema',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$greeting，${account.userName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        account.server.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'Cascadia Mono',
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: AppRadius.borderRadius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                ),
                child: IconButton(
                  key: const ValueKey('home-refresh'),
                  tooltip: '刷新首页',
                  visualDensity: VisualDensity.compact,
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HomeHeroCarousel extends StatefulWidget {
  const _HomeHeroCarousel({
    required this.items,
    required this.continueWatchingItems,
    required this.dailyRecommendations,
    required this.active,
    required this.planningItemId,
    required this.onActiveIndexChanged,
    required this.onPlay,
    required this.onDetails,
  });

  final List<MediaItem> items;
  final List<MediaItem> continueWatchingItems;
  final bool dailyRecommendations;
  final bool active;
  final String? planningItemId;
  final ValueChanged<int> onActiveIndexChanged;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onDetails;

  @override
  State<_HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<_HomeHeroCarousel> {
  static const _autoAdvanceInterval = Duration(seconds: 6);
  static const int _virtualItemCount = 10000;

  late PageController _controller;
  Timer? _timer;
  int _currentIndex = 0;
  late int _currentVirtualPage;
  bool _hovering = false;
  bool _disableAnimations = false;
  Animation<double>? _secondaryAnimation;

  void _onSecondaryAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _scheduleNext();
    } else if (status == AnimationStatus.forward ||
        status == AnimationStatus.completed) {
      _timer?.cancel();
      _timer = null;
    }
  }

  int _toVirtualPage(int realIndex) {
    if (widget.items.length <= 1) return 0;
    final middle = _virtualItemCount ~/ 2;
    final base = middle - (middle % widget.items.length);
    return base + (realIndex % widget.items.length);
  }

  @override
  void initState() {
    super.initState();
    _currentVirtualPage = _toVirtualPage(0);
    _controller = PageController(initialPage: _currentVirtualPage);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    final secAnim = modalRoute?.secondaryAnimation;
    if (secAnim != _secondaryAnimation) {
      _secondaryAnimation?.removeStatusListener(_onSecondaryAnimationStatus);
      _secondaryAnimation = secAnim;
      _secondaryAnimation?.addStatusListener(_onSecondaryAnimationStatus);
    }
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
      _currentVirtualPage = _toVirtualPage(0);
      if (_controller.hasClients) {
        _controller.jumpToPage(_currentVirtualPage);
      }
    }
    _scheduleNext();
  }

  @override
  void dispose() {
    _secondaryAnimation?.removeStatusListener(_onSecondaryAnimationStatus);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = null;
    final isRouteCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!widget.active ||
        !isRouteCurrent ||
        _disableAnimations ||
        _hovering ||
        widget.items.length < 2) {
      return;
    }
    _timer = Timer(_autoAdvanceInterval, () => _move(1));
  }

  Future<void> _move(int direction) async {
    if (widget.items.length < 2 || !_controller.hasClients) return;
    final targetPage = _currentVirtualPage + direction;
    if (_disableAnimations) {
      _controller.jumpToPage(targetPage);
    } else {
      await _controller.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 620),
        curve: const Cubic(0.2, 0.0, 0.0, 1.0),
      );
    }
    if (!mounted) return;
    _scheduleNext();
  }

  Future<void> _jumpToIndex(int targetRealIndex) async {
    if (!_controller.hasClients || widget.items.isEmpty) return;
    final currentReal = _currentIndex;
    var delta = targetRealIndex - currentReal;
    if (delta > widget.items.length / 2) {
      delta -= widget.items.length;
    } else if (delta < -widget.items.length / 2) {
      delta += widget.items.length;
    }
    final targetVirtual = _currentVirtualPage + delta;
    if (_disableAnimations) {
      _controller.jumpToPage(targetVirtual);
    } else {
      await _controller.animateToPage(
        targetVirtual,
        duration: const Duration(milliseconds: 550),
        curve: const Cubic(0.2, 0.0, 0.0, 1.0),
      );
    }
    if (!mounted) return;
    _scheduleNext();
  }

  void _onVirtualPageChanged(int virtualIndex) {
    _currentVirtualPage = virtualIndex;
    final realIndex =
        widget.items.isEmpty ? 0 : virtualIndex % widget.items.length;
    if (_currentIndex != realIndex) {
      setState(() => _currentIndex = realIndex);
      widget.onActiveIndexChanged(realIndex);
    }
    _scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final wideScreen = constraints.maxWidth >= 1200;
        final ultraWide = constraints.maxWidth >= 1600;
        final totalHeight = compact
            ? 420.0
            : ultraWide
                ? 580.0
                : wideScreen
                    ? 540.0
                    : 480.0;

        return MouseRegion(
          onEnter: (_) {
            if (!_hovering) setState(() => _hovering = true);
            _timer?.cancel();
          },
          onExit: (_) {
            if (_hovering) setState(() => _hovering = false);
            _scheduleNext();
          },
          child: SizedBox(
            key: const ValueKey('home-hero'),
            height: totalHeight,
            child: _VisionLiquidGlassPanel(
              radius: AppRadius.value,
              hasBackdropBlur: false,
              blur: 32,
              topAlpha: 0.16,
              bottomAlpha: 0.05,
              borderAlpha: 0.28,
              padding: EdgeInsets.zero,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Full-Bleed Panoramic Billboard PageView
                  PageView.builder(
                    key: const ValueKey('daily-recommendation-carousel'),
                    controller: _controller,
                    allowImplicitScrolling: false,
                    itemCount: widget.items.length > 1
                        ? _virtualItemCount
                        : widget.items.length,
                    onPageChanged: _onVirtualPageChanged,
                    itemBuilder: (context, virtualIndex) {
                      final realIndex = widget.items.isEmpty
                          ? 0
                          : virtualIndex % widget.items.length;
                      final item = widget.items[realIndex];
                      return AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          double delta = 0.0;
                          if (_controller.hasClients &&
                              _controller.position.haveDimensions) {
                            final page = _controller.page ??
                                _currentVirtualPage.toDouble();
                            delta = (page - virtualIndex).clamp(-1.0, 1.0);
                          }
                          final scale = 1.0 - (delta.abs() * 0.032);
                          final opacity =
                              (1.0 - (delta.abs() * 0.40)).clamp(0.0, 1.0);
                          return Transform.scale(
                            scale: scale,
                            child: Opacity(opacity: opacity, child: child),
                          );
                        },
                        child: _HomeHero(
                          key: ValueKey('hero-slide-${item.id}'),
                          item: item,
                          dailyRecommendation: widget.dailyRecommendations,
                          planning: widget.planningItemId == item.id,
                          hovering: _hovering,
                          onPlay: () => widget.onPlay(item),
                          onDetails: () => widget.onDetails(item),
                        ),
                      );
                    },
                  ),

                  // Edge Navigation Controls - seamlessly integrated into canvas edges (边缘隐形)
                  if (widget.items.length > 1) ...[
                    Positioned(
                      left: compact ? 10 : 18,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _EdgeNavButton(
                          key: const ValueKey('hero-previous'),
                          icon: Icons.chevron_left_rounded,
                          tooltip: '上一条',
                          visible: _hovering,
                          onTap: () => unawaited(_move(-1)),
                        ),
                      ),
                    ),
                    Positioned(
                      right: compact ? 10 : 18,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _EdgeNavButton(
                          key: const ValueKey('hero-next'),
                          icon: Icons.chevron_right_rounded,
                          tooltip: '下一条',
                          visible: _hovering,
                          onTap: () => unawaited(_move(1)),
                        ),
                      ),
                    ),
                  ],

                  // Bottom-Right Integrated Index Dock
                  if (widget.items.length > 1)
                    Positioned(
                      bottom: compact ? 16 : 22,
                      right: compact ? 18 : 28,
                      child: _HeroIndexDock(
                        currentIndex: _currentIndex,
                        itemCount: widget.items.length,
                        onTapIndex: (i) => unawaited(_jumpToIndex(i)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EdgeNavButton extends StatefulWidget {
  const _EdgeNavButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.visible = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool visible;

  @override
  State<_EdgeNavButton> createState() => _EdgeNavButtonState();
}

class _EdgeNavButtonState extends State<_EdgeNavButton> {
  bool _buttonHovered = false;

  @override
  Widget build(BuildContext context) {
    final isVisible = widget.visible || _buttonHovered;

    return Tooltip(
      message: isVisible ? widget.tooltip : '',
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: isVisible ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _buttonHovered = true),
        onExit: (_) => setState(() => _buttonHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: RepaintBoundary(
            child: AnimatedOpacity(
              opacity: isVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: _buttonHovered ? 44 : 38,
                height: _buttonHovered ? 44 : 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _buttonHovered
                      ? Colors.white.withValues(alpha: 0.32)
                      : const Color(0x66080B12),
                  border: Border.all(
                    color: _buttonHovered
                        ? Colors.white.withValues(alpha: 0.65)
                        : Colors.white.withValues(alpha: 0.22),
                    width: _buttonHovered ? 1.2 : 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _buttonHovered ? 0.45 : 0.22,
                      ),
                      blurRadius: _buttonHovered ? 14 : 8,
                      offset: const Offset(0, 2),
                    ),
                    if (_buttonHovered)
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.16),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  widget.icon,
                  size: _buttonHovered ? 24 : 22,
                  color: Colors.white.withValues(
                    alpha: _buttonHovered ? 1.0 : 0.88,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroIndexDock extends StatelessWidget {
  const _HeroIndexDock({
    required this.currentIndex,
    required this.itemCount,
    required this.onTapIndex,
  });

  final int currentIndex;
  final int itemCount;
  final ValueChanged<int> onTapIndex;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 1) return const SizedBox.shrink();
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x75080B12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              label: '第 ${currentIndex + 1} 条，共 $itemCount 条每日推荐',
              child: Text(
                '${(currentIndex + 1).toString().padLeft(2, '0')} / '
                '${itemCount.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 9,
              color: Colors.white.withValues(alpha: 0.22),
            ),
            const SizedBox(width: 8),
            ...List.generate(itemCount, (i) {
              final active = i == currentIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: InkWell(
                  onTap: () => onTapIndex(i),
                  borderRadius: BorderRadius.circular(4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: active ? 16 : 5,
                    height: 4,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.5),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _EditorialMetadataRow extends StatelessWidget {
  const _EditorialMetadataRow({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final elements = <Widget>[];

    void addElement(Widget w) {
      if (elements.isNotEmpty) {
        elements.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text(
              '·',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.40),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      }
      elements.add(w);
    }

    if (item.productionYear != null) {
      addElement(
        Text(
          '${item.productionYear}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.90),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
        ),
      );
    }

    addElement(
      Text(
        _kindLabel(item.kind),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.90),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
        ),
      ),
    );

    if (item.runTime != null && item.runTime!.inMinutes > 0) {
      addElement(
        Text(
          '${item.runTime!.inMinutes} 分钟',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
        ),
      );
    }

    if (item.communityRating != null && item.communityRating! > 0) {
      addElement(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.star_rounded,
              size: 15,
              color: Color(0xFFFBBF24),
            ),
            const SizedBox(width: 3),
            Text(
              item.communityRating!.toStringAsFixed(1),
              style: const TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
              ),
            ),
          ],
        ),
      );
    }

    if (item.officialRating != null && item.officialRating!.isNotEmpty) {
      addElement(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.40),
              width: 0.8,
            ),
          ),
          child: Text(
            item.officialRating!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.90),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    }

    addElement(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: Colors.white.withValues(alpha: 0.14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 0.8,
          ),
        ),
        child: const Text(
          '4K',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            fontFamily: 'Cascadia Mono',
          ),
        ),
      ),
    );

    addElement(
      Text(
        '杜比视界',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.75),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
        ),
      ),
    );

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: elements,
    );
  }
}

class _HomeHero extends ConsumerWidget {
  const _HomeHero({
    super.key,
    required this.item,
    required this.dailyRecommendation,
    required this.planning,
    this.hovering = false,
    required this.onPlay,
    required this.onDetails,
  });

  final MediaItem item;
  final bool dailyRecommendation;
  final bool planning;
  final bool hovering;
  final VoidCallback onPlay;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final livePos = ref.watch(
      globalPlaybackCoordinatorProvider.select((s) => s.positionFor(item.id)),
    );
    final effectivePos = (livePos != null && livePos > Duration.zero)
        ? livePos
        : item.resumePosition;
    final resumable = effectivePos > Duration.zero;
    final progress = item.runTime == null || item.runTime == Duration.zero
        ? 0.0
        : (effectivePos.inMilliseconds / item.runTime!.inMilliseconds).clamp(
            0.0,
            1.0,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final wideScreen = constraints.maxWidth >= 1100;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. High-fidelity full-bleed backdrop artwork with hover breathing effect
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedScale(
                  scale: hovering ? 1.038 : 1.0,
                  duration: const Duration(milliseconds: 750),
                  curve: Curves.easeOutCubic,
                  child: _HeroArtwork(item: item),
                ),
              ),
            ),

            // 2. Dual-axis cinematic lighting gradient
            // Horizontal left-to-right vignette (ensuring 100% typography contrast)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xF5080B12),
                      const Color(0xD8080B12),
                      const Color(0x75080B12),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.38, 0.65, 1.0],
                  ),
                ),
              ),
            ),
            // Bottom vignette
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [
                      const Color(0xD0080B12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Top subtle vignette for header badges
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0x75080B12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // 3. Left-Anchored Expansive Content Lockup
            Positioned(
              left: compact ? 44 : 60,
              bottom: compact ? 20 : 32,
              top: compact ? 20 : 30,
              right: compact
                  ? 20
                  : (constraints.maxWidth * 0.36).clamp(300.0, 500.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Integrated eyebrow row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        size: 13,
                        color: Color(0xFFFBBF24),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        dailyRecommendation
                            ? '每日精选推荐'
                            : resumable
                            ? '空间续播'
                            : '精选放映',
                        style: const TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Large Cinematic Title
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 24 : (wideScreen ? 36 : 30),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.18,
                      shadows: const [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 18,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Integrated Editorial Metadata Line
                  _EditorialMetadataRow(item: item),

                  // Synopsis / Overview
                  if (item.overview != null &&
                      item.overview!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      item.overview!,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: compact ? 12.5 : 13.5,
                        height: 1.5,
                        shadows: const [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 10,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Resumable progress bar
                  if (resumable) ...[
                    const SizedBox(height: 10),
                    _ProjectionProgress(
                      value: progress,
                      position: effectivePos,
                      duration: item.runTime,
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Action Buttons
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('home-hero-play'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0A0C12),
                          shape: AppRadius.shape,
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 20 : 26,
                            vertical: compact ? 12 : 14,
                          ),
                          elevation: 6,
                          shadowColor: Colors.black.withValues(alpha: 0.4),
                        ),
                        onPressed: planning ? null : onPlay,
                        icon: planning
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded, size: 22),
                        label: Text(
                          resumable ? '继续播放' : '立即播放',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: compact ? 13 : 15,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.32),
                            width: 1.1,
                          ),
                          shape: AppRadius.shape,
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 18 : 22,
                            vertical: compact ? 12 : 14,
                          ),
                        ),
                        onPressed: planning ? null : onDetails,
                        icon: const Icon(Icons.info_outline_rounded, size: 19),
                        label: Text(
                          '查看详情',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: compact ? 13 : 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
    return PeekMediaImage(
      uri: uri,
      headers: item.imageHeaders,
      kind: PeekMediaImageKind.backdrop,
      fit: BoxFit.cover,
      alignment: Alignment.centerRight,
      placeholderIconSize: 72,
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
            borderRadius: AppRadius.borderRadius,
            child: LinearProgressIndicator(
              key: const ValueKey('home-hero-progress'),
              value: value,
              minHeight: 4,
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.24),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '看到 ${_time(position)}${duration == null ? '' : ' / ${_time(duration!)}'}',
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'Cascadia Mono',
              fontSize: 12,
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
    required this.railId,
    required this.libraryActionLabel,
    required this.onOpen,
    required this.onHover,
    required this.onOpenLibrary,
  });

  final String title;
  final String eyebrow;
  final List<MediaItem> items;
  final bool portrait;
  final bool compact;
  final String railId;
  final String libraryActionLabel;
  final ValueChanged<MediaItem> onOpen;
  final ValueChanged<MediaItem> onHover;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final width = portrait
        ? (compact ? 142.0 : 170.0)
        : (compact ? 244.0 : 294.0);
    final height = portrait
        ? (compact ? 264.0 : 316.0)
        : (compact ? 196.0 : 224.0);
    return _VisionLiquidGlassPanel(
      radius: AppRadius.value,
      blur: 30,
      topAlpha: 0.13,
      bottomAlpha: 0.05,
      borderAlpha: 0.28,
      padding: EdgeInsets.all(compact ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: AppRadius.borderRadius,
                      ),
                      child: Text(
                        eyebrow,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cascadia Mono',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                  shape: AppRadius.shape,
                ),
                onPressed: onOpenLibrary,
                child: Text(libraryActionLabel),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PeekHorizontalRail(
            railId: 'home-track-$railId',
            semanticLabel: title,
            height: height,
            itemCount: items.length,
            itemExtent: width,
            itemBuilder: (context, index) => _HomeMediaCard(
              item: items[index],
              portrait: portrait,
              onOpen: () => onOpen(items[index]),
              onHover: () => onHover(items[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeMediaCard extends ConsumerWidget {
  const _HomeMediaCard({
    required this.item,
    required this.portrait,
    required this.onOpen,
    required this.onHover,
  });

  final MediaItem item;
  final bool portrait;
  final VoidCallback onOpen;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final livePos = ref.watch(
      globalPlaybackCoordinatorProvider.select((s) => s.positionFor(item.id)),
    );
    final effectivePos = (livePos != null && livePos > Duration.zero)
        ? livePos
        : item.resumePosition;
    final progress = item.runTime == null || item.runTime == Duration.zero
        ? 0.0
        : (effectivePos.inMilliseconds / item.runTime!.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: PeekContextMenuRegion(
        items: (context) => [
          PeekContextMenuItem(
            id: 'open',
            label: '查看详情',
            icon: Icons.info_outline_rounded,
            onTap: onOpen,
          ),
        ],
        child: Semantics(
          button: true,
          label: '${item.name}，${_kindLabel(item.kind)}',
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: AppRadius.borderRadius,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.26),
                width: 1.1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Peek3DCard(
                    onTap: onOpen,
                    borderRadius: AppRadius.value,
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
                              minHeight: 4,
                              color: Colors.white,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.24,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _itemMetadata(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
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

class _CardArtwork extends StatelessWidget {
  const _CardArtwork({required this.item, required this.portrait});

  final MediaItem item;
  final bool portrait;

  @override
  Widget build(BuildContext context) {
    final uri = portrait ? item.imageUri : item.backdropUri ?? item.imageUri;
    return PeekMediaImage(
      uri: uri,
      headers: item.imageHeaders,
      kind: item.kind == MediaItemKind.episode
          ? PeekMediaImageKind.episode
          : portrait
          ? PeekMediaImageKind.poster
          : PeekMediaImageKind.backdrop,
      fit: BoxFit.cover,
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
    return _VisionLiquidGlassPanel(
      radius: AppRadius.value,
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 280),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              error == null
                  ? Icons.video_library_outlined
                  : Icons.cloud_off_outlined,
              size: 42,
              color: Colors.white70,
            ),
            const SizedBox(height: 16),
            Text(
              error == null ? '片库已经准备好' : '首页内容暂时无法读取',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              error ?? '播放过的内容和最近添加项目会出现在这里。',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
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
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: AppRadius.shape,
                  ),
                  onPressed: onOpenLibrary,
                  icon: const Icon(Icons.video_library_rounded),
                  label: const Text('打开媒体库'),
                ),
              ],
            ),
          ],
        ),
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
    return _VisionLiquidGlassPanel(
      radius: AppRadius.value,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Colors.white70,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title == null ? message : '$title：$message',
              style: const TextStyle(color: Colors.white),
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
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: AppRadius.borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
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
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: AppRadius.borderRadius,
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
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: AppRadius.borderRadius,
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
