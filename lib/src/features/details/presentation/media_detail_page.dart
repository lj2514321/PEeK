import 'dart:async';
import 'dart:ui';

import 'package:embyplayer/src/app/app_chrome.dart';
import 'package:embyplayer/src/app/app_routes.dart';
import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_horizontal_rail.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/details/presentation/identify_dialog.dart';
import 'package:embyplayer/src/features/details/presentation/person_works_page.dart';
import 'package:embyplayer/src/features/player/data/external_player_service.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/presentation/global_playback_coordinator.dart';
import 'package:embyplayer/src/features/scrobble/presentation/bangumi_summary_card.dart';
import 'package:embyplayer/src/features/download/presentation/batch_download_sheet.dart';
import 'package:embyplayer/src/features/library/presentation/media_library_page.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MediaDetailPage extends ConsumerStatefulWidget {
  const MediaDetailPage({
    super.key,
    required this.account,
    required this.initialItem,
    this.isWarmup = false,
  });

  final AuthenticatedServer? account;
  final MediaItem initialItem;
  final bool isWarmup;

  @override
  ConsumerState<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends ConsumerState<MediaDetailPage> {
  late MediaItem _item = widget.initialItem;
  List<MediaItem> _similarItems = const [];
  List<MediaItem> _episodes = const [];
  List<MediaItem> _collections = const [];
  List<MediaItem> _collectionItems = const [];
  final GlobalKey _collectionSectionKey = GlobalKey();
  int _selectedSeasonNumber = 1;
  bool _loadingDetails = false;
  bool _planningPlayback = false;
  String? _planningEpisodeId;
  bool _updatingFavorite = false;
  bool _updatingPlayed = false;
  String? _detailError;
  String? _similarError;
  String? _playbackError;
  String? _selectedMediaSourceId;
  final _scrollController = SmoothScrollController();
  final ValueNotifier<bool> _showScrolledTitleNotifier = ValueNotifier<bool>(
    false,
  );
  bool _hydrated = false;
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeStatusListener;
  Timer? _hydrationFallbackTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialItem.kind == MediaItemKind.person &&
        widget.account != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          Peek3DPageRoute(
            builder: (_) => PersonWorksPage(
              account: widget.account!,
              person: MediaPerson(
                id: widget.initialItem.id,
                name: widget.initialItem.name,
                type: 'Actor',
                imageUri: widget.initialItem.imageUri,
                imageHeaders: widget.initialItem.imageHeaders,
              ),
              onOpen: (work) => Navigator.of(context).pushReplacement(
                Peek3DPageRoute(
                  builder: (_) => MediaDetailPage(
                    account: widget.account,
                    initialItem: work,
                  ),
                ),
              ),
            ),
          ),
        );
      });
      return;
    }
    if (widget.initialItem.mediaSources.isNotEmpty) {
      _selectedMediaSourceId = widget.initialItem.mediaSources.first.id;
    }
    _selectedSeasonNumber = widget.initialItem.parentIndexNumber ?? 1;
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeRouteAnimation();
  }

  void _subscribeRouteAnimation() {
    if (widget.isWarmup ||
        _hydrated ||
        (widget.initialItem.kind == MediaItemKind.person &&
            widget.account != null)) {
      return;
    }

    if (AppMotion.isTest) {
      _scheduleHydration();
      return;
    }

    final modalRoute = ModalRoute.of(context);
    final animation = modalRoute?.animation;
    if (animation == null || animation.isCompleted) {
      _scheduleHydration();
      return;
    }

    if (_routeAnimation == null) {
      _routeAnimation = animation;
      _routeStatusListener = (status) {
        if (status == AnimationStatus.completed) {
          _cleanRouteListener();
          _scheduleHydration();
        }
      };
      animation.addStatusListener(_routeStatusListener!);

      _hydrationFallbackTimer = Timer(const Duration(milliseconds: 460), () {
        if (mounted && !_hydrated) {
          _cleanRouteListener();
          _scheduleHydration();
        }
      });
    }
  }

  void _cleanRouteListener() {
    _hydrationFallbackTimer?.cancel();
    _hydrationFallbackTimer = null;
    if (_routeAnimation != null && _routeStatusListener != null) {
      _routeAnimation!.removeStatusListener(_routeStatusListener!);
      _routeStatusListener = null;
      _routeAnimation = null;
    }
  }

  void _scheduleHydration() {
    if (_hydrated || !mounted) return;
    _hydrated = true;
    _cleanRouteListener();
    _syncSpatialAmbient();
    unawaited(_loadDetails());
  }

  void _syncSpatialAmbient() {
    if (!mounted) return;
    final ambientUri = _item.backdropUri ?? _item.imageUri;
    SpatialAmbientController.instance.update(
      itemId: _item.id,
      imageUri: ambientUri,
      imageHeaders: _item.imageHeaders,
      paletteSeed: _item.id.hashCode.abs(),
    );
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final show = _scrollController.offset > 160;
      if (_showScrolledTitleNotifier.value != show) {
        _showScrolledTitleNotifier.value = show;
      }
    }
  }

  @override
  void dispose() {
    _cleanRouteListener();
    _showScrolledTitleNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isSeriesOrSeason =>
      _item.kind == MediaItemKind.series || _item.kind == MediaItemKind.season;

  Map<int, List<MediaItem>> get _seasonEpisodeMap {
    final map = <int, List<MediaItem>>{};
    for (final ep in _episodes) {
      final seasonNum = ep.parentIndexNumber ?? 1;
      map.putIfAbsent(seasonNum, () => []).add(ep);
    }
    return map;
  }

  List<int> get _availableSeasonNumbers {
    final numbers = _seasonEpisodeMap.keys.toList()..sort();
    return numbers.isEmpty ? [1] : numbers;
  }

  Future<void> _loadDetails({
    bool forceRefresh = false,
    bool force = false,
  }) async {
    final account = widget.account;
    if (account == null || _item.isLocal) return;
    if (_loadingDetails && !force) return;
    setState(() {
      _loadingDetails = true;
      _detailError = null;
      _similarError = null;
    });
    final service = ref.read(mediaLibraryProvider);
    try {
      final detailsFuture = service.getItem(
        account,
        widget.initialItem.id,
        forceRefresh: forceRefresh,
      );
      final similarFuture =
          _item.kind == MediaItemKind.movie ||
              _item.kind == MediaItemKind.series
          ? service.getSimilar(account, _item.id)
          : Future.value(const <MediaItem>[]);

      final episodesFuture = _isSeriesOrSeason
          ? service.getEpisodesForSeries(
              account,
              seriesId: _item.seriesId ?? _item.id,
              forceRefresh: forceRefresh,
            )
          : Future.value(const <MediaItem>[]);

      final collectionsFuture = !_item.isLocal
          ? service.getCollectionsForItem(
              account,
              widget.initialItem.id,
              forceRefresh: forceRefresh,
            )
          : Future.value(const <MediaItem>[]);

      final details = await detailsFuture;
      final similar = await similarFuture;
      final episodes = await episodesFuture;
      final collections = await collectionsFuture;

      List<MediaItem> collectionItems = const [];
      if (collections.isNotEmpty) {
        try {
          collectionItems = await service.getCollectionItems(
            account,
            collections.first.id,
            forceRefresh: forceRefresh,
          );
        } catch (_) {
          // Ignore collection items loading error
        }
      }

      if (!mounted) return;
      setState(() {
        _item = details;
        if (details.mediaSources.isNotEmpty) {
          if (_selectedMediaSourceId == null ||
              details.mediaSources.every(
                (s) => s.id != _selectedMediaSourceId,
              )) {
            _selectedMediaSourceId = details.mediaSources.first.id;
          }
        }
        _similarItems = similar;
        _episodes = episodes;
        _collections = collections;
        _collectionItems = collectionItems;
        if (episodes.isNotEmpty) {
          final seasons = _availableSeasonNumbers;
          if (!seasons.contains(_selectedSeasonNumber)) {
            _selectedSeasonNumber = seasons.first;
          }
        }
      });
      _syncSpatialAmbient();
    } on MediaLibraryException catch (error) {
      if (mounted) setState(() => _detailError = error.message);
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _playItem(
    MediaItem targetItem, {
    bool fromBeginning = false,
    bool? forceExternalPlayer,
  }) async {
    setState(() {
      _planningPlayback = true;
      _planningEpisodeId = targetItem.id;
      _playbackError = null;
    });
    try {
      final coordinator = ref.read(globalPlaybackCoordinatorProvider.notifier);
      final livePos = fromBeginning
          ? Duration.zero
          : coordinator.getEffectivePosition(targetItem.id);
      final effectiveTarget =
          (livePos != null && livePos > targetItem.resumePosition)
          ? targetItem.copyWith(resumePosition: livePos)
          : targetItem;
      final prepared = await ref
          .read(playbackPreparationProvider)
          .prepare(
            widget.account,
            effectiveTarget,
            fromBeginning: fromBeginning,
            startPosition: livePos,
            mediaSourceId: targetItem.id == _item.id
                ? _selectedMediaSourceId
                : null,
          );
      if (!mounted) return;

      final shouldUseExternal =
          forceExternalPlayer ?? prepared.settings.useExternalPlayer;
      if (shouldUseExternal) {
        final service = ref.read(externalPlayerServiceProvider);
        final launched = await service.launch(
          prepared.plan,
          executablePath: prepared.settings.externalPlayerPath,
          seekPosition: fromBeginning ? Duration.zero : null,
          title: targetItem.name,
        );
        if (!mounted) return;
        if (launched) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已在外部播放器中启动《${targetItem.name}》')),
          );
          if (!targetItem.isLocal) await _loadDetails(forceRefresh: true);
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
        skipIntroPreferences: prepared.settings.skipIntroPreferences,
        danmakuPreferences: prepared.settings.danmakuPreferences,
        enableMiniPlayer: prepared.settings.enableMiniPlayer,
        longPressSpeed: prepared.settings.longPressSpeed,
        ref: ref,
      );
      if (mounted && !targetItem.isLocal) {
        await _loadDetails(forceRefresh: true);
      }
    } on PlaybackServiceException catch (error) {
      if (mounted) setState(() => _playbackError = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _playbackError = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _planningPlayback = false;
          _planningEpisodeId = null;
        });
      }
    }
  }

  bool get _playable =>
      _item.kind == MediaItemKind.movie ||
      _item.kind == MediaItemKind.episode ||
      _item.kind == MediaItemKind.video ||
      _item.kind == MediaItemKind.audio ||
      _item.kind == MediaItemKind.series ||
      _item.kind == MediaItemKind.season;

  bool get _canMarkPlayed =>
      _playable ||
      _item.kind == MediaItemKind.series ||
      _item.kind == MediaItemKind.season;

  Future<void> _toggleFavorite() async {
    final account = widget.account;
    if (account == null || _item.isLocal) return;
    if (_updatingFavorite) return;
    final target = !_item.favorite;
    setState(() => _updatingFavorite = true);
    try {
      await ref
          .read(mediaLibraryProvider)
          .setFavorite(account, _item.id, favorite: target);
      if (!mounted) return;
      setState(() => _item = _item.copyWith(favorite: target));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(target ? '已加入收藏' : '已取消收藏')));
    } on MediaLibraryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新收藏失败：${error.message}')));
    } finally {
      if (mounted) setState(() => _updatingFavorite = false);
    }
  }

  Future<void> _togglePlayed() async {
    final account = widget.account;
    if (account == null || _item.isLocal) return;
    if (_updatingPlayed) return;
    final target = !_item.played;
    setState(() => _updatingPlayed = true);
    try {
      await ref
          .read(mediaLibraryProvider)
          .setPlayed(account, _item.id, played: target);
      if (!mounted) return;
      setState(
        () => _item = _item.copyWith(
          played: target,
          resumePosition: target ? Duration.zero : _item.resumePosition,
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(target ? '已标记为已观看' : '已标记为未观看')));
    } on MediaLibraryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新观看状态失败：${error.message}')));
    } finally {
      if (mounted) setState(() => _updatingPlayed = false);
    }
  }

  Future<void> _openIdentifyDialog() async {
    final account = widget.account;
    if (account == null || _item.isLocal) return;
    final updated = await peekShowDialog<bool>(
      context: context,
      builder: (context) => IdentifyDialog(account: account, item: _item),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已向服务器提交识别匹配，正在重新加载《${_item.name}》...')),
      );
      await _loadDetails(forceRefresh: true);
    }
  }

  Future<void> _openBatchDownloadDialog() async {
    final account = widget.account;
    if (account == null || _item.isLocal) return;

    final count = await peekShowDialog<int>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: BatchDownloadSheet(
          item: _item,
          episodes: _episodes,
          account: account,
        ),
      ),
    );

    if (count != null && count > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.spotlight,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '已添加 $count 个任务至离线下载中心',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _openSimilar(MediaItem item) async {
    await Navigator.of(context).push<void>(
      Peek3DPageRoute(
        builder: (context) =>
            MediaDetailPage(account: widget.account, initialItem: item),
      ),
    );
  }

  void _scrollToCollection() {
    final context = _collectionSectionKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _openCollectionItem(MediaItem item) async {
    if (item.id == _item.id) return;
    await Navigator.of(context).push<void>(
      Peek3DPageRoute(
        builder: (context) =>
            MediaDetailPage(account: widget.account, initialItem: item),
      ),
    );
  }

  Future<void> _openPerson(MediaPerson person) async {
    final account = widget.account;
    if (account == null) return;
    await Navigator.of(context).push<void>(
      Peek3DPageRoute(
        builder: (context) => PersonWorksPage(
          account: account,
          person: person,
          onOpen: _openPersonWork,
        ),
      ),
    );
  }

  void _openPersonWork(MediaItem item) {
    Navigator.of(context).push<void>(
      Peek3DPageRoute(
        builder: (context) =>
            MediaDetailPage(account: widget.account, initialItem: item),
      ),
    );
  }

  Future<void> _openTagWorks(String tag) async {
    await peekShowDialog<void>(
      context: context,
      builder: (dialogContext) => _TagWorksDialog(
        account: widget.account,
        tag: tag,
        onOpenMedia: (work) {
          Navigator.of(dialogContext).pop();
          Navigator.of(context).push<void>(
            Peek3DPageRoute(
              builder: (context) =>
                  MediaDetailPage(account: widget.account, initialItem: work),
            ),
          );
        },
        onOpenInLibrary: widget.account == null
            ? null
            : () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push<void>(
                  Peek3DPageRoute(
                    builder: (context) => MediaLibraryPage(
                      account: widget.account,
                      initialTag: tag,
                      onGoHome: () => Navigator.of(
                        context,
                      ).popUntil((route) => route.isFirst),
                    ),
                  ),
                );
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(globalPlaybackCoordinatorProvider, (prev, next) {
      final wasActive =
          prev?.mode == PlaybackPresentationMode.mini ||
          prev?.mode == PlaybackPresentationMode.window ||
          prev?.mode == PlaybackPresentationMode.full;
      if (wasActive && next.mode == PlaybackPresentationMode.hidden) {
        if (mounted && !_item.isLocal) {
          unawaited(_loadDetails(forceRefresh: true));
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted && !_item.isLocal) {
              unawaited(_loadDetails(forceRefresh: true, force: true));
            }
          });
        }
      }
    });
    final currentSeasonEpisodes =
        _seasonEpisodeMap[_selectedSeasonNumber] ??
        (_episodes.isNotEmpty ? _episodes : const <MediaItem>[]);

    return PopScope<MediaItem>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_item);
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: AmbientBackdrop(
          child: Stack(
            children: [
              PeekSmoothScroll(
                controller: _scrollController,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _DetailHero(
                        item: _item,
                        collectionName: _collections.firstOrNull?.name,
                        onTapCollection: _scrollToCollection,
                        onTapTag: _openTagWorks,
                        loading: _loadingDetails,
                        playable: _playable,
                        planningPlayback:
                            _planningPlayback &&
                            (_planningEpisodeId == _item.id ||
                                _planningEpisodeId == null),
                        updatingFavorite: _updatingFavorite,
                        updatingPlayed: _updatingPlayed,
                        canMarkPlayed: _canMarkPlayed,
                        showUserStateActions: !_item.isLocal,
                        onPlay: () => _playItem(_item),
                        onPlayFromBeginning: () =>
                            _playItem(_item, fromBeginning: true),
                        onPlayExternal: () =>
                            _playItem(_item, forceExternalPlayer: true),
                        onToggleFavorite: _toggleFavorite,
                        onTogglePlayed: _togglePlayed,
                        onIdentify: !_item.isLocal && widget.account != null
                            ? _openIdentifyDialog
                            : null,
                        onDownload: !_item.isLocal && widget.account != null
                            ? _openBatchDownloadDialog
                            : null,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 64),
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
                                    onAction: () => _playItem(_item),
                                    error: true,
                                  ),
                                if (_detailError != null ||
                                    _playbackError != null)
                                  const SizedBox(height: 20),

                                // Season and Episode Picker (for Series / Seasons)
                                if (_isSeriesOrSeason &&
                                    _episodes.isNotEmpty) ...[
                                  _EpisodePickerSection(
                                    item: _item,
                                    seasonNumbers: _availableSeasonNumbers,
                                    selectedSeason: _selectedSeasonNumber,
                                    episodes: currentSeasonEpisodes,
                                    planningEpisodeId: _planningEpisodeId,
                                    onSelectSeason: (season) {
                                      setState(
                                        () => _selectedSeasonNumber = season,
                                      );
                                    },
                                    onPlayEpisode: (ep) => _playItem(ep),
                                  ),
                                  const SizedBox(height: 32),
                                ],

                                // Synopsis & Technical Specs Bento Layout
                                _OverviewAndSpecsBento(
                                  item: _item,
                                  selectedMediaSourceId: _selectedMediaSourceId,
                                  onTapTag: _openTagWorks,
                                  onSelectMediaSource: (id) {
                                    setState(() => _selectedMediaSourceId = id);
                                  },
                                ),

                                // Collection (if media belongs to a BoxSet / Collection)
                                if (_collections.isNotEmpty) ...[
                                  const SizedBox(height: 32),
                                  _CollectionSection(
                                    key: _collectionSectionKey,
                                    currentItem: _item,
                                    collection: _collections.first,
                                    items: _collectionItems,
                                    onOpenItem: _openCollectionItem,
                                  ),
                                ],

                                // Cast & Crew
                                if (_item.people.isNotEmpty) ...[
                                  const SizedBox(height: 32),
                                  _CastSection(
                                    people: _item.people,
                                    onOpen: _openPerson,
                                  ),
                                ],

                                // Similar Recommendations
                                if (_similarItems.isNotEmpty) ...[
                                  const SizedBox(height: 32),
                                  _SimilarSection(
                                    items: _similarItems,
                                    onOpen: _openSimilar,
                                  ),
                                ] else if (_similarError != null) ...[
                                  const SizedBox(height: 20),
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

              // Top Floating Navigation Bar Overlay
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _showScrolledTitleNotifier,
                  builder: (context, showScrolledTitle, _) =>
                      _DetailFloatingNavBar(
                        item: _item,
                        showTitle: showScrolledTitle,
                        onBack: () => Navigator.of(context).pop(_item),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailFloatingNavBar extends StatelessWidget {
  const _DetailFloatingNavBar({
    required this.item,
    required this.showTitle,
    required this.onBack,
  });

  final MediaItem item;
  final bool showTitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final rightMargin = defaultTargetPlatform == TargetPlatform.windows
        ? AppChrome.windowControlsWidth + 10.0
        : 16.0;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, 0, rightMargin, 0),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: showTitle ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            return Container(
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.18 * t),
                    Colors.white.withValues(alpha: 0.06 * t),
                  ],
                ),
                borderRadius: AppRadius.borderRadius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.32 * t),
                  width: 1.2,
                ),
                boxShadow: t > 0.02
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28 * t),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : const [],
              ),
              child: Builder(
                builder: (context) {
                  final barContent = Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        // Floating Back Button
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                              alpha: 0.14 + (0.06 * (1 - t)),
                            ),
                            borderRadius: AppRadius.borderRadius,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.30),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: 0.28 * (1 - t),
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
                            tooltip: '返回',
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: onBack,
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Scrolled-in Title
                        Expanded(
                          child: IgnorePointer(
                            ignoring: !showTitle,
                            child: Opacity(
                              opacity: t,
                              child: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (t <= 0.01) {
                    return barContent;
                  }
                  return ClipRRect(
                    borderRadius: AppRadius.borderRadius,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: barContent,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.item,
    this.collectionName,
    this.onTapCollection,
    this.onTapTag,
    required this.loading,
    required this.playable,
    required this.planningPlayback,
    required this.updatingFavorite,
    required this.updatingPlayed,
    required this.canMarkPlayed,
    required this.showUserStateActions,
    required this.onPlay,
    required this.onPlayFromBeginning,
    this.onPlayExternal,
    required this.onToggleFavorite,
    required this.onTogglePlayed,
    this.onIdentify,
    this.onDownload,
  });

  final MediaItem item;
  final String? collectionName;
  final VoidCallback? onTapCollection;
  final ValueChanged<String>? onTapTag;
  final bool loading;
  final bool playable;
  final bool planningPlayback;
  final bool updatingFavorite;
  final bool updatingPlayed;
  final bool canMarkPlayed;
  final bool showUserStateActions;
  final VoidCallback onPlay;
  final VoidCallback onPlayFromBeginning;
  final VoidCallback? onPlayExternal;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePlayed;
  final VoidCallback? onIdentify;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Fluid Background Backdrop Layer with Seamless Hardware-Accelerated Alpha Dissolve
        Positioned.fill(
          child: RepaintBoundary(child: _Backdrop(item: item)),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.canvas.withValues(alpha: 0.55),
                  AppColors.canvas.withValues(alpha: 0.55),
                  AppColors.canvas.withValues(alpha: 0.8425),
                  AppColors.canvas,
                ],
                stops: const [0.0, 0.45, 0.78, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.42),
                  Colors.black.withValues(alpha: 0.16),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),

        // Hero Info Area
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 768;
                final poster = _DetailPoster(item: item);
                final copy = _DetailCopy(
                  item: item,
                  collectionName: collectionName,
                  onTapCollection: onTapCollection,
                  onTapTag: onTapTag,
                  compact: compact,
                  playable: playable,
                  planningPlayback: planningPlayback,
                  updatingFavorite: updatingFavorite,
                  updatingPlayed: updatingPlayed,
                  canMarkPlayed: canMarkPlayed,
                  showUserStateActions: showUserStateActions,
                  onPlay: onPlay,
                  onPlayFromBeginning: onPlayFromBeginning,
                  onPlayExternal: onPlayExternal,
                  onToggleFavorite: onToggleFavorite,
                  onTogglePlayed: onTogglePlayed,
                  onIdentify: onIdentify,
                  onDownload: onDownload,
                );

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 20 : 36,
                    compact ? 56 : 88,
                    compact ? 20 : 36,
                    compact ? 24 : 48,
                  ),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(width: 140, child: poster),
                            ),
                            const SizedBox(height: 16),
                            copy,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 220, child: poster),
                            const SizedBox(width: 36),
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
            top: 72,
            right: 24,
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
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
    return PeekMediaImage(
      uri: uri,
      headers: item.imageHeaders,
      kind: PeekMediaImageKind.backdrop,
      fit: BoxFit.cover,
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
      child: PosterAmbientGlow(
        glowColor: const Color(0x454A90E2),
        borderRadius: AppRadius.value,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: AppRadius.borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 32,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: PeekMediaImage(
            uri: item.imageUri,
            headers: item.imageHeaders,
            kind: PeekMediaImageKind.poster,
            placeholderIconSize: 58,
          ),
        ),
      ),
    );
  }
}

class _DetailCopy extends ConsumerWidget {
  const _DetailCopy({
    required this.item,
    this.collectionName,
    this.onTapCollection,
    this.onTapTag,
    required this.compact,
    required this.playable,
    required this.planningPlayback,
    required this.updatingFavorite,
    required this.updatingPlayed,
    required this.canMarkPlayed,
    required this.showUserStateActions,
    required this.onPlay,
    required this.onPlayFromBeginning,
    this.onPlayExternal,
    required this.onToggleFavorite,
    required this.onTogglePlayed,
    this.onIdentify,
    this.onDownload,
  });

  final MediaItem item;
  final String? collectionName;
  final VoidCallback? onTapCollection;
  final ValueChanged<String>? onTapTag;
  final bool compact;
  final bool playable;
  final bool planningPlayback;
  final bool updatingFavorite;
  final bool updatingPlayed;
  final bool canMarkPlayed;
  final bool showUserStateActions;
  final VoidCallback onPlay;
  final VoidCallback onPlayFromBeginning;
  final VoidCallback? onPlayExternal;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePlayed;
  final VoidCallback? onIdentify;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final livePos = ref.watch(
      globalPlaybackCoordinatorProvider.select((s) => s.positionFor(item.id)),
    );
    final effectivePos = (livePos != null && livePos > Duration.zero)
        ? livePos
        : item.resumePosition;
    final resume = effectivePos > Duration.zero;
    final badges = _buildSpecBadges(item);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category / Subtitle / Collection
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.spotlight.withValues(alpha: 0.16),
                borderRadius: AppRadius.borderRadius,
                border: Border.all(
                  color: AppColors.spotlight.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Text(
                _kindLabel(item.kind),
                style: const TextStyle(
                  color: AppColors.spotlight,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            if (collectionName != null && collectionName!.isNotEmpty) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: onTapCollection,
                borderRadius: AppRadius.borderRadius,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.15),
                    borderRadius: AppRadius.borderRadius,
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.collections_bookmark_rounded,
                        size: 13,
                        color: AppColors.cyan,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '所属合集 · $collectionName',
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (item.seriesName != null &&
                item.kind != MediaItemKind.series) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  item.seriesName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Title
        Text(
          item.name,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontSize: compact ? 30 : 42,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.15,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),

        // Tagline
        if (item.tagline != null && item.tagline!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '“${item.tagline!}”',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontStyle: FontStyle.italic,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 18),

        // Spec Badges
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: badges.map((badge) => _SpecChip(spec: badge)).toList(),
        ),

        // Tags
        if (item.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in item.tags.take(6))
                _TagChip(
                  key: ValueKey('detail-tag-$tag'),
                  tag: tag,
                  onTap: () => onTapTag?.call(tag),
                ),
              if (item.tags.length > 6)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: AppRadius.borderRadius,
                  ),
                  child: Text(
                    '+${item.tags.length - 6}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],

        // Action Buttons
        if (playable) ...[
          const SizedBox(height: 28),
          _PlaybackActions(
            compact: compact,
            resume: resume,
            planning: planningPlayback,
            resumeLabel: _position(effectivePos),
            onPlay: onPlay,
            onPlayFromBeginning: onPlayFromBeginning,
            onPlayExternal: onPlayExternal,
          ),
        ],

        if (showUserStateActions) ...[
          const SizedBox(height: 14),
          _UserStateActions(
            compact: compact,
            favorite: item.favorite,
            played: item.played,
            canMarkPlayed: canMarkPlayed,
            updatingFavorite: updatingFavorite,
            updatingPlayed: updatingPlayed,
            onToggleFavorite: onToggleFavorite,
            onTogglePlayed: onTogglePlayed,
            onIdentify: onIdentify,
            onDownload: onDownload,
          ),
        ],
      ],
    );
  }

  List<_SpecData> _buildSpecBadges(MediaItem item) {
    final list = <_SpecData>[];

    // Year
    if (item.productionYear != null) {
      list.add(_SpecData(label: '${item.productionYear}', isHighlight: false));
    }

    // Runtime
    if (item.runTime != null && item.runTime!.inMinutes > 0) {
      list.add(
        _SpecData(label: '${item.runTime!.inMinutes} 分钟', isHighlight: false),
      );
    }

    // Community Rating
    if (item.communityRating != null) {
      list.add(
        _SpecData(
          label: '★ ${item.communityRating!.toStringAsFixed(1)}',
          isHighlight: true,
          highlightColor: const Color(0xFFFFB800),
        ),
      );
    }

    // Official Rating
    if (item.officialRating != null && item.officialRating!.isNotEmpty) {
      list.add(_SpecData(label: item.officialRating!, isHighlight: false));
    }

    // Video Resolution (4K, 1080p, 720p)
    if (item.width != null) {
      if (item.width! >= 3800 ||
          (item.height != null && item.height! >= 2100)) {
        list.add(const _SpecData(label: '4K UHD', isHighlight: true));
      } else if (item.width! >= 1900 ||
          (item.height != null && item.height! >= 1000)) {
        list.add(const _SpecData(label: '1080P', isHighlight: false));
      }
    }

    // Codec
    if (item.videoCodec != null && item.videoCodec!.isNotEmpty) {
      list.add(
        _SpecData(label: item.videoCodec!.toUpperCase(), isHighlight: false),
      );
    }

    // Multi-version badge
    if (item.mediaSources.length > 1) {
      list.add(
        _SpecData(
          label: '${item.mediaSources.length} 个版本可选',
          isHighlight: true,
          highlightColor: AppColors.spotlight,
        ),
      );
    }

    // Genres
    for (final genre in item.genres.take(3)) {
      list.add(_SpecData(label: genre, isHighlight: false));
    }

    if (item.isLocal) {
      list.add(const _SpecData(label: '本地资源', isHighlight: false));
    }

    return list;
  }

  String _position(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    return hours > 0 ? '$hours 小时 $minutes 分' : '$minutes 分钟';
  }
}

class _SpecData {
  const _SpecData({
    required this.label,
    required this.isHighlight,
    this.highlightColor,
  });

  final String label;
  final bool isHighlight;
  final Color? highlightColor;
}

class _SpecChip extends StatelessWidget {
  const _SpecChip({required this.spec});

  final _SpecData spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: spec.isHighlight
            ? (spec.highlightColor ?? AppColors.spotlight).withValues(
                alpha: 0.16,
              )
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: AppRadius.borderRadius,
        border: Border.all(
          color: spec.isHighlight
              ? (spec.highlightColor ?? AppColors.spotlight).withValues(
                  alpha: 0.45,
                )
              : Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Text(
        spec.label,
        style: TextStyle(
          color: spec.isHighlight
              ? (spec.highlightColor ?? AppColors.spotlight)
              : Colors.white.withValues(alpha: 0.85),
          fontSize: 12,
          fontWeight: spec.isHighlight ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({super.key, required this.tag, this.onTap});

  final String tag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.spotlight.withValues(alpha: 0.12),
            borderRadius: AppRadius.borderRadius,
            border: Border.all(
              color: AppColors.spotlight.withValues(alpha: 0.32),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '#$tag',
                style: const TextStyle(
                  color: AppColors.spotlight,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 8,
                  color: AppColors.spotlight.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackActions extends StatelessWidget {
  const _PlaybackActions({
    required this.compact,
    required this.resume,
    required this.planning,
    required this.resumeLabel,
    required this.onPlay,
    required this.onPlayFromBeginning,
    this.onPlayExternal,
  });

  final bool compact;
  final bool resume;
  final bool planning;
  final String resumeLabel;
  final VoidCallback onPlay;
  final VoidCallback onPlayFromBeginning;
  final VoidCallback? onPlayExternal;

  @override
  Widget build(BuildContext context) {
    final primary = PeekMagneticButton(
      enabled: !planning,
      maxOffset: 5.0,
      pressScale: 0.94,
      hoverScale: 1.04,
      child: FilledButton.icon(
        onPressed: planning ? null : onPlay,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.spotlight,
          foregroundColor: Colors.black,
          shape: const StadiumBorder(),
          elevation: 6,
          shadowColor: AppColors.spotlight.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        ),
        icon: planning
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.black,
                ),
              )
            : const Icon(Icons.play_arrow_rounded, size: 22),
        label: Text(
          planning
              ? '正在加载播放…'
              : resume
              ? '继续播放 · $resumeLabel'
              : '立即播放',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );

    final restart = OutlinedButton.icon(
      onPressed: planning ? null : onPlayFromBeginning,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
      ),
      icon: const Icon(Icons.replay_rounded, size: 18),
      label: const Text('从头播放', style: TextStyle(fontWeight: FontWeight.w600)),
    );

    final externalPlay = OutlinedButton.icon(
      key: const ValueKey('detail-play-external'),
      onPressed: planning ? null : onPlayExternal,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
      ),
      icon: const Icon(Icons.open_in_new_rounded, size: 17),
      label: const Text('外部播放器', style: TextStyle(fontWeight: FontWeight.w600)),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          if (resume) ...[const SizedBox(height: 10), restart],
          if (onPlayExternal != null) ...[
            const SizedBox(height: 10),
            externalPlay,
          ],
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        primary,
        if (resume) restart,
        if (onPlayExternal != null) externalPlay,
      ],
    );
  }
}

class _UserStateActions extends StatelessWidget {
  const _UserStateActions({
    required this.compact,
    required this.favorite,
    required this.played,
    required this.canMarkPlayed,
    required this.updatingFavorite,
    required this.updatingPlayed,
    required this.onToggleFavorite,
    required this.onTogglePlayed,
    this.onIdentify,
    this.onDownload,
  });

  final bool compact;
  final bool favorite;
  final bool played;
  final bool canMarkPlayed;
  final bool updatingFavorite;
  final bool updatingPlayed;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePlayed;
  final VoidCallback? onIdentify;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final favoriteButton = OutlinedButton.icon(
      key: const ValueKey('detail-favorite-button'),
      onPressed: updatingFavorite ? null : onToggleFavorite,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        backgroundColor: favorite
            ? AppColors.spotlight.withValues(alpha: 0.14)
            : null,
        foregroundColor: favorite ? AppColors.spotlight : Colors.white70,
        side: BorderSide(
          color: favorite
              ? AppColors.spotlight.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      icon: updatingFavorite
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 18,
            ),
      label: Text(favorite ? '已收藏' : '收藏'),
    );

    final playedButton = OutlinedButton.icon(
      key: const ValueKey('detail-played-button'),
      onPressed: updatingPlayed ? null : onTogglePlayed,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        backgroundColor: played
            ? AppColors.success.withValues(alpha: 0.14)
            : null,
        foregroundColor: played ? AppColors.success : Colors.white70,
        side: BorderSide(
          color: played
              ? AppColors.success.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      icon: updatingPlayed
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              played
                  ? Icons.check_circle_rounded
                  : Icons.check_circle_outline_rounded,
              size: 18,
            ),
      label: Text(played ? '已观看' : '标为已观看'),
    );

    final downloadButton = OutlinedButton.icon(
      key: const ValueKey('detail-download-button'),
      onPressed: onDownload,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        foregroundColor: AppColors.cyan,
        side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.35)),
      ),
      icon: const Icon(Icons.downloading_rounded, size: 18),
      label: const Text('离线缓存'),
    );

    final identifyButton = OutlinedButton.icon(
      key: const ValueKey('detail-inline-identify-button'),
      onPressed: onIdentify,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        foregroundColor: Colors.white70,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
      label: const Text('修正识别'),
    );

    if (compact) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          favoriteButton,
          if (canMarkPlayed) playedButton,
          if (onDownload != null) downloadButton,
          if (onIdentify != null) identifyButton,
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        favoriteButton,
        if (canMarkPlayed) playedButton,
        if (onDownload != null) downloadButton,
        if (onIdentify != null) identifyButton,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 剧集选集与分季列表 (Season and Episode Picker)
// ---------------------------------------------------------------------------

class _EpisodePickerSection extends StatelessWidget {
  const _EpisodePickerSection({
    required this.item,
    required this.seasonNumbers,
    required this.selectedSeason,
    required this.episodes,
    required this.planningEpisodeId,
    required this.onSelectSeason,
    required this.onPlayEpisode,
  });

  final MediaItem item;
  final List<int> seasonNumbers;
  final int selectedSeason;
  final List<MediaItem> episodes;
  final String? planningEpisodeId;
  final ValueChanged<int> onSelectSeason;
  final ValueChanged<MediaItem> onPlayEpisode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppGlass.visionOSDecoration(
        elevated: true,
        glowColor: const Color(0x304A90E2),
        borderOpacity: 0.25,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.video_library_rounded,
                size: 20,
                color: AppColors.spotlight,
              ),
              const SizedBox(width: 8),
              Text(
                '剧集选集',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              Text(
                '本季共 ${episodes.length} 集',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Season Tabs (if more than 1 season or special)
          if (seasonNumbers.length > 1) ...[
            PeekSmoothScroll(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: seasonNumbers.map((season) {
                    final isSelected = season == selectedSeason;
                    final label = season == 0 ? '特别篇' : '第 $season 季';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        onSelected: (_) => onSelectSeason(season),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Episode Cards Rail
          PeekHorizontalRail(
            railId: 'detail-episodes-$selectedSeason',
            semanticLabel: '剧集列表',
            height: 240,
            itemCount: episodes.length,
            itemExtent: 280,
            itemBuilder: (context, index) {
              final ep = episodes[index];
              return _EpisodeCard(
                episode: ep,
                isPlanning: planningEpisodeId == ep.id,
                onPlay: () => onPlayEpisode(ep),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EpisodeCard extends ConsumerWidget {
  const _EpisodeCard({
    required this.episode,
    required this.isPlanning,
    required this.onPlay,
  });

  final MediaItem episode;
  final bool isPlanning;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final livePos = ref.watch(
      globalPlaybackCoordinatorProvider.select(
        (s) => s.positionFor(episode.id),
      ),
    );
    final effectiveResume = (livePos != null && livePos > Duration.zero)
        ? livePos
        : episode.resumePosition;
    final epNum = episode.indexNumber != null ? 'E${episode.indexNumber}' : '';
    final hasResume = effectiveResume > Duration.zero;

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.borderRadius,
          onTap: isPlanning ? null : onPlay,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: AppRadius.borderRadius,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 16:9 Thumbnail
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: AppRadius.circular,
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PeekMediaImage(
                          uri: episode.backdropUri ?? episode.imageUri,
                          headers: episode.imageHeaders,
                          kind: PeekMediaImageKind.backdrop,
                        ),
                        Container(color: Colors.black.withValues(alpha: 0.25)),
                        // Play Icon Center
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isPlanning
                                  ? Colors.black54
                                  : AppColors.spotlight.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                            ),
                            child: isPlanning
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.black,
                                    size: 22,
                                  ),
                          ),
                        ),
                        // Episode Index Tag
                        if (epNum.isNotEmpty)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: AppRadius.borderRadius,
                              ),
                              child: Text(
                                epNum,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        // Resume Progress Bar
                        if (hasResume &&
                            episode.runTime != null &&
                            episode.runTime!.inMilliseconds > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value:
                                  (effectiveResume.inMilliseconds /
                                          episode.runTime!.inMilliseconds)
                                      .clamp(0.0, 1.0),
                              backgroundColor: Colors.black45,
                              color: AppColors.spotlight,
                              minHeight: 3,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Title and Info
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episode.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        episode.runTime != null &&
                                episode.runTime!.inMinutes > 0
                            ? '${episode.runTime!.inMinutes} 分钟'
                            : '单集',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
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
    );
  }
}

// ---------------------------------------------------------------------------
// 剧情简介与技术档案 Bento Grid
// ---------------------------------------------------------------------------

class _OverviewAndSpecsBento extends StatelessWidget {
  const _OverviewAndSpecsBento({
    required this.item,
    this.selectedMediaSourceId,
    this.onSelectMediaSource,
    this.onTapTag,
  });

  final MediaItem item;
  final String? selectedMediaSourceId;
  final ValueChanged<String>? onSelectMediaSource;
  final ValueChanged<String>? onTapTag;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final overviewWidget = _OverviewCard(item: item, onTapTag: onTapTag);
        final specsWidget = _MediaSpecsCard(
          item: item,
          selectedMediaSourceId: selectedMediaSourceId,
          onSelectMediaSource: onSelectMediaSource,
        );

        final bangumiCard = BangumiSummaryCard(
          mediaName: item.seriesName ?? item.name,
        );

        if (!isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              overviewWidget,
              bangumiCard,
              const SizedBox(height: 20),
              specsWidget,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [overviewWidget, bangumiCard],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(flex: 2, child: specsWidget),
          ],
        );
      },
    );
  }
}

class _OverviewCard extends StatefulWidget {
  const _OverviewCard({required this.item, this.onTapTag});

  final MediaItem item;
  final ValueChanged<String>? onTapTag;

  @override
  State<_OverviewCard> createState() => _OverviewCardState();
}

class _OverviewCardState extends State<_OverviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final overviewText = widget.item.overview ?? '服务器暂未提供简介。';
    final isLongText = overviewText.length > 220;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppGlass.visionOSDecoration(
        elevated: true,
        glowColor: const Color(0x204A90E2),
        borderOpacity: 0.22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_stories_rounded,
                size: 20,
                color: AppColors.spotlight,
              ),
              const SizedBox(width: 8),
              Text(
                '剧情简介',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedCrossFade(
            duration: AppMotion.standard,
            crossFadeState: _expanded || !isLongText
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Text(
              overviewText,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            secondChild: Text(
              overviewText,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (isLongText) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: AppRadius.borderRadius,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? '收起简介' : '展开全部简介',
                      style: const TextStyle(
                        color: AppColors.spotlight,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.spotlight,
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (widget.item.tags.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.label_rounded,
                  size: 16,
                  color: AppColors.spotlight,
                ),
                const SizedBox(width: 6),
                const Text(
                  '媒体标签',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${widget.item.tags.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in widget.item.tags)
                  _TagChip(
                    key: ValueKey('overview-tag-$tag'),
                    tag: tag,
                    onTap: () => widget.onTapTag?.call(tag),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaSpecsCard extends StatelessWidget {
  const _MediaSpecsCard({
    required this.item,
    this.selectedMediaSourceId,
    this.onSelectMediaSource,
  });

  final MediaItem item;
  final String? selectedMediaSourceId;
  final ValueChanged<String>? onSelectMediaSource;

  @override
  Widget build(BuildContext context) {
    final activeSource = item.mediaSources.firstWhere(
      (s) => s.id == selectedMediaSourceId,
      orElse: () => item.mediaSources.isNotEmpty
          ? item.mediaSources.first
          : const MediaSourceInfo(id: '', name: ''),
    );
    final hasActive = activeSource.id.isNotEmpty;

    final width = hasActive ? (activeSource.width ?? item.width) : item.width;
    final height = hasActive
        ? (activeSource.height ?? item.height)
        : item.height;
    final videoCodec = hasActive
        ? (activeSource.videoCodec ?? item.videoCodec)
        : item.videoCodec;
    final videoRange = hasActive ? activeSource.videoRange : null;
    final audioCodec = hasActive ? activeSource.audioCodec : null;
    final bitrate = hasActive
        ? (activeSource.bitrate ?? item.bitrate)
        : item.bitrate;
    final container = hasActive
        ? (activeSource.container ?? item.container)
        : item.container;
    final fileSize = hasActive
        ? (activeSource.fileSize ?? item.fileSize)
        : item.fileSize;
    final path = hasActive
        ? (activeSource.path ?? item.sourcePath)
        : item.sourcePath;

    final entries = <_SpecEntry>[
      if (width != null && height != null)
        _SpecEntry(
          icon: Icons.hd_rounded,
          label: '画面分辨率',
          value: '$width × $height${width >= 3800 ? " (4K UHD)" : ""}',
        ),
      if (videoCodec != null && videoCodec.isNotEmpty)
        _SpecEntry(
          icon: Icons.movie_filter_rounded,
          label: '视频编码',
          value:
              videoCodec.toUpperCase() +
              (videoRange != null && videoRange.isNotEmpty
                  ? ' · $videoRange'
                  : ''),
        ),
      if (audioCodec != null && audioCodec.isNotEmpty)
        _SpecEntry(
          icon: Icons.audiotrack_rounded,
          label: '音频编码',
          value: audioCodec.toUpperCase(),
        ),
      if (bitrate != null && bitrate > 0)
        _SpecEntry(
          icon: Icons.speed_rounded,
          label: '总码率',
          value: '${(bitrate / (1000 * 1000)).toStringAsFixed(1)} Mbps',
        ),
      if (container != null && container.isNotEmpty)
        _SpecEntry(
          icon: Icons.folder_zip_rounded,
          label: '封装格式',
          value: container.toUpperCase(),
        ),
      if (fileSize != null)
        _SpecEntry(
          icon: Icons.storage_rounded,
          label: '文件大小',
          value: _formatBytes(fileSize),
        ),
      if (path != null && path.isNotEmpty)
        _SpecEntry(
          icon: Icons.insert_drive_file_rounded,
          label: item.isLocal ? '本地路径' : '服务端路径',
          value: path,
        ),
    ];

    if (entries.isEmpty) {
      entries.add(
        _SpecEntry(
          icon: Icons.info_outline_rounded,
          label: '媒体规格',
          value: item.isLocal ? '本地媒体资源' : '流媒体服务器源',
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppGlass.visionOSDecoration(
        elevated: true,
        glowColor: const Color(0x204A90E2),
        borderOpacity: 0.22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_rounded,
                size: 20,
                color: AppColors.spotlight,
              ),
              const SizedBox(width: 8),
              Text(
                '媒体规格档案',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          if (item.mediaSources.length > 1) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.layers_rounded,
                  size: 15,
                  color: AppColors.spotlight,
                ),
                const SizedBox(width: 6),
                const Text(
                  '版本切换',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${item.mediaSources.length} 个规格源)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final src in item.mediaSources)
                  _buildVersionCapsule(
                    src,
                    isSelected:
                        src.id ==
                        (selectedMediaSourceId ?? item.mediaSources.first.id),
                    onTap: () => onSelectMediaSource?.call(src.id),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Colors.white12),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(height: 18, color: Colors.white10),
            Row(
              children: [
                Icon(entries[i].icon, size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                Text(
                  entries[i].label,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    entries[i].value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVersionCapsule(
    MediaSourceInfo source, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final labelParts = <String>[];
    if (source.resolutionLabel.isNotEmpty) {
      labelParts.add(source.resolutionLabel);
    }
    if (source.videoCodec != null && source.videoCodec!.isNotEmpty) {
      labelParts.add(source.videoCodec!.toUpperCase());
    }
    if (source.formattedFileSize.isNotEmpty) {
      labelParts.add(source.formattedFileSize);
    }
    final detail = labelParts.join(' · ');

    return InkWell(
      key: ValueKey('version-source-${source.id}'),
      borderRadius: AppRadius.borderRadius,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.spotlight.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: AppRadius.borderRadius,
          border: Border.all(
            color: isSelected
                ? AppColors.spotlight
                : Colors.white.withValues(alpha: 0.15),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 13,
                    color: AppColors.spotlight,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  source.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? AppColors.spotlight : Colors.white,
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected
                      ? AppColors.spotlight.withValues(alpha: 0.85)
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

class _SpecEntry {
  const _SpecEntry({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

// ---------------------------------------------------------------------------
// 演职人员阵容 (Cast & Crew)
// ---------------------------------------------------------------------------

class _CastSection extends StatelessWidget {
  const _CastSection({required this.people, required this.onOpen});

  final List<MediaPerson> people;
  final ValueChanged<MediaPerson> onOpen;

  @override
  Widget build(BuildContext context) {
    final actors = people
        .where((person) {
          final type = person.type.toLowerCase();
          return type == 'actor' || type == 'gueststar';
        })
        .take(24)
        .toList();
    final visiblePeople = actors.isEmpty ? people.take(24).toList() : actors;
    if (visiblePeople.isEmpty) return const SizedBox.shrink();

    return _DetailPanel(
      eyebrow: 'CAST & CREW',
      title: '演员阵容',
      icon: Icons.group_rounded,
      child: PeekHorizontalRail(
        railId: 'detail-cast',
        semanticLabel: '演员阵容',
        height: 230,
        itemCount: visiblePeople.length,
        itemExtent: 128,
        itemBuilder: (context, index) => _PersonCard(
          person: visiblePeople[index],
          onOpen: () => onOpen(visiblePeople[index]),
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onOpen});

  final MediaPerson person;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '查看 ${person.name} 的全部作品',
      child: Tooltip(
        message: '查看 ${person.name} 的全部作品',
        child: SizedBox(
          width: 128,
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.borderRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('person-card-${person.id}'),
              borderRadius: AppRadius.borderRadius,
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: AppRadius.borderRadius,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1,
                        ),
                      ),
                      child: PeekMediaImage(
                        uri: person.imageUri,
                        headers: person.imageHeaders,
                        kind: PeekMediaImageKind.person,
                        placeholderBackground: AppColors.surfaceHigh,
                        placeholderIcon: Icons.person_outline_rounded,
                        placeholderIconSize: 42,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                    child: Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 3, 2, 4),
                    child: Text(
                      person.role ?? _personTypeLabel(person.type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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

// ---------------------------------------------------------------------------
// 相似推荐 (More Like This)
// ---------------------------------------------------------------------------

class _SimilarSection extends StatelessWidget {
  const _SimilarSection({required this.items, required this.onOpen});

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return _DetailPanel(
      eyebrow: 'MORE LIKE THIS',
      title: '相似推荐',
      icon: Icons.recommend_rounded,
      child: PeekHorizontalRail(
        railId: 'detail-similar',
        semanticLabel: '相似推荐',
        height: 290,
        itemCount: items.length,
        itemExtent: 144,
        itemBuilder: (context, index) => _SimilarCard(
          item: items[index],
          onOpen: () => onOpen(items[index]),
        ),
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
      width: 144,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: AppRadius.borderRadius,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: AppRadius.borderRadius,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    child: PeekMediaImage(
                      uri: item.imageUri,
                      headers: item.imageHeaders,
                      kind: PeekMediaImageKind.poster,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.productionYear?.toString() ?? _kindLabel(item.kind),
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
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

// ---------------------------------------------------------------------------
// Collection Section Widgets
// ---------------------------------------------------------------------------

class _CollectionSection extends StatelessWidget {
  const _CollectionSection({
    super.key,
    required this.currentItem,
    required this.collection,
    required this.items,
    required this.onOpenItem,
  });

  final MediaItem currentItem;
  final MediaItem collection;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final countLabel = items.isNotEmpty ? '共 ${items.length} 部作品' : '';
    final title = countLabel.isNotEmpty
        ? '所属合集 · ${collection.name}（$countLabel）'
        : '所属合集 · ${collection.name}';

    return _DetailPanel(
      eyebrow: 'COLLECTION',
      title: title,
      icon: Icons.auto_awesome_motion_rounded,
      child: items.isEmpty
          ? _CollectionBannerCard(collection: collection)
          : PeekHorizontalRail(
              railId: 'detail-collection-${collection.id}',
              semanticLabel: '所属合集作品',
              height: 290,
              itemCount: items.length,
              itemExtent: 144,
              itemBuilder: (context, index) {
                final item = items[index];
                final isCurrent = item.id == currentItem.id;
                return _CollectionItemCard(
                  item: item,
                  isCurrent: isCurrent,
                  onOpen: () => onOpenItem(item),
                );
              },
            ),
    );
  }
}

class _CollectionItemCard extends StatelessWidget {
  const _CollectionItemCard({
    required this.item,
    required this.isCurrent,
    required this.onOpen,
  });

  final MediaItem item;
  final bool isCurrent;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 144,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isCurrent ? null : onOpen,
          borderRadius: AppRadius.borderRadius,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: AppRadius.borderRadius,
                      border: Border.all(
                        color: isCurrent
                            ? AppColors.spotlight
                            : Colors.white.withValues(alpha: 0.12),
                        width: isCurrent ? 2 : 1,
                      ),
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: AppColors.spotlight.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PeekMediaImage(
                          uri: item.imageUri,
                          headers: item.imageHeaders,
                          kind: PeekMediaImageKind.poster,
                        ),
                        if (isCurrent)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: AppRadius.borderRadius,
                                border: Border.all(
                                  color: AppColors.spotlight.withValues(
                                    alpha: 0.6,
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: const Text(
                                '当前',
                                style: TextStyle(
                                  color: AppColors.spotlight,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                    color: isCurrent ? AppColors.spotlight : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.productionYear?.toString() ?? _kindLabel(item.kind),
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
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

class _CollectionBannerCard extends StatelessWidget {
  const _CollectionBannerCard({required this.collection});

  final MediaItem collection;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: AppRadius.borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          if (collection.imageUri != null) ...[
            ClipRRect(
              borderRadius: AppRadius.borderRadius,
              child: SizedBox(
                width: 60,
                height: 90,
                child: PeekMediaImage(
                  uri: collection.imageUri,
                  headers: collection.imageHeaders,
                  kind: PeekMediaImageKind.poster,
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  collection.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (collection.overview != null &&
                    collection.overview!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    collection.overview!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.eyebrow,
    required this.title,
    required this.child,
    this.icon,
  });

  final String eyebrow;
  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppGlass.visionOSDecoration(
        elevated: true,
        glowColor: const Color(0x204A90E2),
        borderOpacity: 0.22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppColors.spotlight),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error
            ? AppColors.error.withValues(alpha: 0.12)
            : AppColors.glassSurface,
        borderRadius: AppRadius.borderRadius,
        border: Border.all(
          color: (error ? AppColors.error : AppColors.spotlight).withValues(
            alpha: 0.3,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: (error ? AppColors.error : Colors.black).withValues(
              alpha: 0.14,
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 13.5)),
          ),
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

class _TagWorksDialog extends ConsumerStatefulWidget {
  const _TagWorksDialog({
    required this.account,
    required this.tag,
    required this.onOpenMedia,
    this.onOpenInLibrary,
  });

  final AuthenticatedServer? account;
  final String tag;
  final ValueChanged<MediaItem> onOpenMedia;
  final VoidCallback? onOpenInLibrary;

  @override
  ConsumerState<_TagWorksDialog> createState() => _TagWorksDialogState();
}

class _TagWorksDialogState extends ConsumerState<_TagWorksDialog> {
  List<MediaItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadWorks);
  }

  Future<void> _loadWorks() async {
    final account = widget.account;
    if (account == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _items = const [];
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(mediaLibraryProvider);
      final result = await service.getItems(
        account,
        tag: widget.tag,
        limit: 40,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _items = result.items;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '读取标签作品失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 620),
        padding: const EdgeInsets.all(24),
        decoration: AppGlass.decoration(elevated: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.spotlight.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.label_rounded,
                    color: AppColors.spotlight,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${widget.tag}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _loading
                            ? '正在读取相关作品…'
                            : _items.isEmpty
                            ? '未找到相关作品'
                            : '共找到 ${_items.length} 部相关媒体',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onOpenInLibrary != null)
                  TextButton.icon(
                    key: const ValueKey('tag-works-open-library'),
                    onPressed: widget.onOpenInLibrary,
                    icon: const Icon(Icons.filter_alt_rounded, size: 16),
                    label: const Text('在媒体库筛选'),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 16),
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(color: AppColors.error),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _loadWorks,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : _items.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无包含该标签的其他内容',
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 140,
                            childAspectRatio: 2 / 3.4,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final it = _items[index];
                        return InkWell(
                          key: ValueKey('tag-work-${it.id}'),
                          onTap: () => widget.onOpenMedia(it),
                          borderRadius: AppRadius.borderRadius,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceHigh,
                                    borderRadius: AppRadius.borderRadius,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                  child: PeekMediaImage(
                                    uri: it.imageUri,
                                    headers: it.imageHeaders,
                                    kind: PeekMediaImageKind.poster,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                it.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                it.productionYear?.toString() ??
                                    _kindLabel(it.kind),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
