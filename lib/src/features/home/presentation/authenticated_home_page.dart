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
                        0,
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
                      padding: EdgeInsets.only(left: leftPadding),
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
                        padding: EdgeInsets.fromLTRB(leftPadding, 14, 0, 0),
                        sliver: SliverToBoxAdapter(
                          child: _HomeSectionNotice(
                            message: _pageError!,
                            onRetry: () => unawaited(_load(forceRefresh: true)),
                          ),
                        ),
                      ),
                    if (_loading && feed == null)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(leftPadding, 24, 0, 0),
                        sliver: const SliverToBoxAdapter(
                          child: _HomeTracksSkeleton(),
                        ),
                      )
                    else if (feed != null)
                      ..._feedSlivers(
                        feed,
                        leftPadding: leftPadding,
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
          compact: compact,
        ),
      if (!feed.latestEpisodes.isEmpty || feed.latestEpisodes.hasError)
        _sectionSliver(
          title: '最新剧集',
          eyebrow: 'FRESH EPISODES',
          section: feed.latestEpisodes,
          portrait: false,
          leftPadding: leftPadding,
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
    required bool compact,
    String? railId,
    String libraryActionLabel = '查看媒体库',
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(leftPadding, compact ? 20 : 26, 0, 0),
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

    return AnimatedSwitcher(
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
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final double topAlpha;
  final double bottomAlpha;
  final double borderAlpha;

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
  static const _autoAdvanceInterval = Duration(hours: 24);

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
    if (!widget.active ||
        _disableAnimations ||
        _hovering ||
        widget.items.length < 2) {
      return;
    }
    _timer = Timer(_autoAdvanceInterval, () => _move(1));
  }

  Future<void> _move(int direction) async {
    if (widget.items.length < 2 || !_controller.hasClients) return;
    final next = (_currentIndex + direction) % widget.items.length;
    final normalized = next < 0 ? widget.items.length - 1 : next;
    await _jumpToIndex(normalized);
  }

  Future<void> _jumpToIndex(int index) async {
    if (!_controller.hasClients) return;
    if (_disableAnimations) {
      _controller.jumpToPage(index);
    } else {
      await _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 480),
        curve: const Cubic(0.12, 0.88, 0.22, 1.0),
      );
    }
    if (!mounted) return;
    _scheduleNext();
  }

  void _pageChanged(int index) {
    setState(() => _currentIndex = index);
    widget.onActiveIndexChanged(index);
    _scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final showSidePod = constraints.maxWidth >= 920;
        const totalHeight = 420.0;

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
            height: totalHeight,
            child: _VisionLiquidGlassPanel(
              radius: AppRadius.value,
              blur: 38,
              topAlpha: 0.16,
              bottomAlpha: 0.06,
              borderAlpha: 0.36,
              padding: EdgeInsets.all(compact ? 16 : 24),
              child: Column(
                children: [
                  // Top Spatial Window Status Bar
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: AppRadius.borderRadius,
                          ),
                          child: Text(
                            compact ? '✨ 空间主视窗' : '✨ 空间主视窗 · 每日精选推荐',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (showSidePod) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.28),
                            borderRadius: AppRadius.borderRadius,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: const Text(
                            'Spatial Audio · Dolby Vision',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Cascadia Mono',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (widget.items.length > 1)
                        _CarouselControls(
                          currentIndex: _currentIndex,
                          itemCount: widget.items.length,
                          onPrevious: () => unawaited(_move(-1)),
                          onNext: () => unawaited(_move(1)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Center Split Stage: Left Spotlight Carousel + Right Spatial Resume Pod
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 7,
                          child: PageView.builder(
                            key: const ValueKey(
                              'daily-recommendation-carousel',
                            ),
                            controller: _controller,
                            allowImplicitScrolling: true,
                            itemCount: widget.items.length,
                            onPageChanged: _pageChanged,
                            itemBuilder: (context, index) {
                              final item = widget.items[index];
                              return AnimatedBuilder(
                                animation: _controller,
                                builder: (context, child) {
                                  double delta = 0.0;
                                  if (_controller.hasClients &&
                                      _controller.position.haveDimensions) {
                                    final page =
                                        _controller.page ??
                                        _currentIndex.toDouble();
                                    delta = (page - index).abs().clamp(
                                      0.0,
                                      1.0,
                                    );
                                  }
                                  final scale = 1.0 - (delta * 0.038);
                                  final opacity = 1.0 - (delta * 0.42);
                                  return Transform.scale(
                                    scale: scale,
                                    child: Opacity(
                                      opacity: opacity,
                                      child: child,
                                    ),
                                  );
                                },
                                child: _HomeHero(
                                  key: ValueKey('hero-slide-${item.id}'),
                                  item: item,
                                  dailyRecommendation:
                                      widget.dailyRecommendations,
                                  planning: widget.planningItemId == item.id,
                                  onPlay: () => widget.onPlay(item),
                                  onDetails: () => widget.onDetails(item),
                                ),
                              );
                            },
                          ),
                        ),
                        if (showSidePod) ...[
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 5,
                            child: AnimatedSwitcher(
                              duration: AppMotion.responsive(
                                context,
                                const Duration(milliseconds: 360),
                              ),
                              switchInCurve: const Cubic(0.16, 1.0, 0.3, 1.0),
                              switchOutCurve: Curves.easeOutCubic,
                              child: _VisionContinueWatchingPod(
                                key: ValueKey(
                                  'continue-pod-${widget.continueWatchingItems.isNotEmpty ? widget.continueWatchingItems.first.id : widget.items[_currentIndex.clamp(0, widget.items.length - 1)].id}',
                                ),
                                resumeItem:
                                    widget.continueWatchingItems.isNotEmpty
                                    ? widget.continueWatchingItems.first
                                    : null,
                                fallbackItem:
                                    widget.items[_currentIndex.clamp(
                                      0,
                                      widget.items.length - 1,
                                    )],
                                onPlay: widget.onPlay,
                                onDetails: widget.onDetails,
                              ),
                            ),
                          ),
                        ],
                      ],
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

/// Right-hand VisionOS Floating Continue Watching Pod inside the Spatial Stage.
class _VisionContinueWatchingPod extends ConsumerWidget {
  const _VisionContinueWatchingPod({
    super.key,
    required this.resumeItem,
    required this.fallbackItem,
    required this.onPlay,
    required this.onDetails,
  });

  final MediaItem? resumeItem;
  final MediaItem fallbackItem;
  final ValueChanged<MediaItem> onPlay;
  final ValueChanged<MediaItem> onDetails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = resumeItem ?? fallbackItem;
    final livePos = ref.watch(
      globalPlaybackCoordinatorProvider.select((s) => s.positionFor(target.id)),
    );
    final effectivePos = (livePos != null && livePos > Duration.zero)
        ? livePos
        : target.resumePosition;
    final progress = target.runTime == null || target.runTime == Duration.zero
        ? (resumeItem != null ? 0.65 : 0.0)
        : (effectivePos.inMilliseconds / target.runTime!.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    final pct = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
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
          color: Colors.white.withValues(alpha: 0.30),
          width: 1.1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    resumeItem != null ? '空间续播舱' : '空间焦点预览',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                resumeItem != null ? '$pct%' : '4K HDR',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ClipRRect(
                borderRadius: AppRadius.borderRadius,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PeekMediaImage(
                      uri: target.backdropUri ?? target.imageUri,
                      headers: target.imageHeaders,
                      kind: PeekMediaImageKind.backdrop,
                      fit: BoxFit.cover,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.72),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _itemMetadata(target),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (effectivePos > Duration.zero)
                                  Text(
                                    '已看 ${_time(effectivePos)}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => onPlay(target),
                            borderRadius: AppRadius.borderRadius,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                borderRadius: AppRadius.borderRadius,
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    size: 16,
                                    color: Colors.black,
                                  ),
                                  SizedBox(width: 2),
                                  Text(
                                    '续播',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
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
          ClipRRect(
            borderRadius: AppRadius.borderRadius,
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : 0.35,
              minHeight: 5,
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
            ),
          ),
        ],
      ),
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: AppRadius.borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: const ValueKey('hero-previous'),
              borderRadius: const BorderRadius.horizontal(
                left: AppRadius.circular,
              ),
              onTap: onPrevious,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(12, 6, 8, 6),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
            Semantics(
              liveRegion: true,
              label: '第 ${currentIndex + 1} 条，共 $itemCount 条每日推荐',
              child: Text(
                '${(currentIndex + 1).toString().padLeft(2, '0')} / '
                '${itemCount.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            InkWell(
              key: const ValueKey('hero-next'),
              borderRadius: const BorderRadius.horizontal(
                right: AppRadius.circular,
              ),
              onTap: onNext,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(8, 6, 12, 6),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHero extends ConsumerWidget {
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
        final compact = constraints.maxWidth < 520;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: AppRadius.borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.26),
              width: 1.1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(opacity: 0.48, child: _HeroArtwork(item: item)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.78),
                    ],
                    stops: const [0.0, 0.52, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(compact ? 18 : 26),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: AppRadius.borderRadius,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Text(
                        dailyRecommendation
                            ? 'SPOTLIGHT // DAILY RECOMMENDATION'
                            : resumable
                            ? 'SPOTLIGHT // CONTINUE WATCHING'
                            : 'SPOTLIGHT // NEW IN YOUR LIBRARY',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cascadia Mono',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(
                              fontSize: compact ? 26 : 38,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _itemMetadata(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    if (!compact && item.overview != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (resumable) ...[
                      const SizedBox(height: 10),
                      _ProjectionProgress(
                        value: progress,
                        position: effectivePos,
                        duration: item.runTime,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('home-hero-play'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0A0C12),
                            shape: AppRadius.shape,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 13,
                            ),
                          ),
                          onPressed: planning ? null : onPlay,
                          icon: planning
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            resumable ? '继续播放' : '立即播放',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.14,
                            ),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.34),
                            ),
                            shape: AppRadius.shape,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 13,
                            ),
                          ),
                          onPressed: planning ? null : onDetails,
                          icon: const Icon(Icons.info_outline_rounded),
                          label: const Text('查看详情'),
                        ),
                      ],
                    ),
                  ],
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
