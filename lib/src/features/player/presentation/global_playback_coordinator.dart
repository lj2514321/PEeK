import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:embyplayer/src/app/app.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/features/analytics/data/viewing_history_store.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_queue.dart';
import 'package:embyplayer/src/features/player/domain/player_window_payload.dart';
import 'package:embyplayer/src/features/player/presentation/playback_page.dart';
import 'package:embyplayer/src/features/player/presentation/playback_runtime.dart';
import 'package:embyplayer/src/features/player/presentation/player_window_coordinator.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

enum PlaybackPresentationMode { hidden, mini, full, window }

class GlobalPlaybackState {
  const GlobalPlaybackState({
    this.mode = PlaybackPresentationMode.hidden,
    this.account,
    this.item,
    this.plan,
    this.queue,
    this.runtime,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.recentPositions = const {},
    this.revision = 0,
  });

  final PlaybackPresentationMode mode;
  final AuthenticatedServer? account;
  final MediaItem? item;
  final PlaybackPlan? plan;
  final PlaybackQueue? queue;
  final PlaybackRuntime? runtime;
  final bool playing;
  final Duration position;
  final Duration duration;
  final Map<String, Duration> recentPositions;
  final int revision;

  Duration? positionFor(String itemId) {
    if (item?.id == itemId && position > Duration.zero) return position;
    return recentPositions[itemId];
  }

  double? progressFor(String itemId, Duration? totalDuration) {
    final pos = positionFor(itemId);
    if (pos == null ||
        totalDuration == null ||
        totalDuration <= Duration.zero) {
      return null;
    }
    return (pos.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0);
  }

  GlobalPlaybackState copyWith({
    PlaybackPresentationMode? mode,
    AuthenticatedServer? account,
    MediaItem? item,
    PlaybackPlan? plan,
    PlaybackQueue? queue,
    PlaybackRuntime? runtime,
    bool? playing,
    Duration? position,
    Duration? duration,
    Map<String, Duration>? recentPositions,
    int? revision,
  }) {
    return GlobalPlaybackState(
      mode: mode ?? this.mode,
      account: account ?? this.account,
      item: item ?? this.item,
      plan: plan ?? this.plan,
      queue: queue ?? this.queue,
      runtime: runtime ?? this.runtime,
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      recentPositions: recentPositions ?? this.recentPositions,
      revision: revision ?? this.revision,
    );
  }
}

final globalPlaybackCoordinatorProvider =
    NotifierProvider<GlobalPlaybackCoordinator, GlobalPlaybackState>(
      GlobalPlaybackCoordinator.new,
    );

class GlobalPlaybackCoordinator extends Notifier<GlobalPlaybackState> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  PlaybackRuntime? _activeRuntime;
  Timer? _miniProgressTimer;

  @override
  GlobalPlaybackState build() {
    ref.onDispose(() {
      _cancelSubscriptions();
      _activeRuntime?.dispose();
    });
    return const GlobalPlaybackState();
  }

  Duration? getEffectivePosition(String itemId) => state.positionFor(itemId);

  void recordPosition(String itemId, Duration position) {
    if (position <= Duration.zero) return;
    final updated = Map<String, Duration>.from(state.recentPositions);
    updated[itemId] = position;
    state = state.copyWith(
      recentPositions: updated,
      revision: state.revision + 1,
    );
  }

  void registerActivePlayback({
    required AuthenticatedServer? account,
    required MediaItem item,
    required PlaybackPlan plan,
    PlaybackQueue? queue,
    required PlaybackRuntime runtime,
    Duration? initialPosition,
  }) {
    _cancelSubscriptions();
    _activeRuntime = runtime;

    final initialPos =
        (initialPosition != null && initialPosition > Duration.zero)
        ? initialPosition
        : runtime.position;
    final updatedPositions = Map<String, Duration>.from(state.recentPositions);
    if (initialPos > Duration.zero) {
      updatedPositions[item.id] = initialPos;
    }

    state = GlobalPlaybackState(
      mode: PlaybackPresentationMode.full,
      account: account,
      item: item,
      plan: plan,
      queue: queue,
      runtime: runtime,
      playing: runtime.playing,
      position: initialPos,
      duration: plan.duration ?? Duration.zero,
      recentPositions: updatedPositions,
      revision: state.revision + 1,
    );

    _subscriptions.add(
      runtime.playingStream.listen((playing) {
        state = state.copyWith(playing: playing);
        _syncMiniProgressTimer();
      }),
    );

    DateTime lastPositionUpdateTime = DateTime.now();
    _subscriptions.add(
      runtime.positionStream.listen((position) {
        if (position > Duration.zero || state.position == Duration.zero) {
          final now = DateTime.now();
          final diff = (position - state.position).abs();
          if (diff >= const Duration(seconds: 1) ||
              now.difference(lastPositionUpdateTime) >=
                  const Duration(milliseconds: 350)) {
            lastPositionUpdateTime = now;
            final recents = Map<String, Duration>.from(state.recentPositions);
            recents[item.id] = position;
            state = state.copyWith(
              position: position,
              recentPositions: recents,
            );
          }
        }
      }),
    );
    _subscriptions.add(
      runtime.durationStream.listen((duration) {
        if (duration > Duration.zero) {
          state = state.copyWith(duration: duration);
        }
      }),
    );
  }

  void registerWindowPlayback({
    required AuthenticatedServer? account,
    required MediaItem item,
    required PlaybackPlan plan,
    PlaybackQueue? queue,
    Duration? initialPosition,
  }) {
    _cancelSubscriptions();
    _activeRuntime = null;

    final initialPos =
        (initialPosition != null && initialPosition > Duration.zero)
        ? initialPosition
        : plan.startPosition;
    final updatedPositions = Map<String, Duration>.from(state.recentPositions);
    if (initialPos > Duration.zero) {
      updatedPositions[item.id] = initialPos;
    }

    state = GlobalPlaybackState(
      mode: PlaybackPresentationMode.window,
      account: account,
      item: item,
      plan: plan,
      queue: queue,
      runtime: null,
      playing: true,
      position: initialPos,
      duration: plan.duration ?? Duration.zero,
      recentPositions: updatedPositions,
      revision: state.revision + 1,
    );
  }

  void reportOptimisticProgress(
    String itemId,
    Duration position, {
    Duration? duration,
    bool? playing,
  }) {
    final updatedPositions = Map<String, Duration>.from(state.recentPositions);
    if (position > Duration.zero) {
      updatedPositions[itemId] = position;
    }
    state = state.copyWith(
      position: position,
      duration: duration ?? state.duration,
      playing: playing ?? state.playing,
      recentPositions: updatedPositions,
      revision: state.revision + 1,
    );
  }

  void updatePlaybackState({bool? playing, Duration? position}) {
    state = state.copyWith(
      playing: playing ?? state.playing,
      position: position ?? state.position,
      revision: state.revision + 1,
    );
  }

  void updateActiveItem(MediaItem item, {PlaybackPlan? plan}) {
    state = state.copyWith(
      item: item,
      plan: plan ?? state.plan,
      revision: state.revision + 1,
    );
  }

  void closeMiniSilently() {
    _cancelSubscriptions();
    _miniProgressTimer?.cancel();
    _miniProgressTimer = null;
    final runtime = state.runtime;
    _activeRuntime = null;
    unawaited(runtime?.pause());
    unawaited(runtime?.dispose().catchError((_) {}));
    state = state.copyWith(
      mode: PlaybackPresentationMode.hidden,
      playing: false,
      revision: state.revision + 1,
    );
  }

  void clearActivePlayback() {
    _cancelSubscriptions();
    _activeRuntime = null;
    state = state.copyWith(
      mode: PlaybackPresentationMode.hidden,
      playing: false,
      revision: state.revision + 1,
    );
  }

  void minimize([BuildContext? context]) {
    if (state.runtime == null || state.item == null) return;
    state = state.copyWith(mode: PlaybackPresentationMode.mini);
    _syncMiniProgressTimer();
    if (context != null) {
      Navigator.maybeOf(context)?.pop();
    }
  }

  void expand([BuildContext? context]) {
    if (state.runtime == null || state.item == null || state.plan == null)
      return;
    final item = state.item!;
    final account = state.account;
    final plan = state.plan!;
    final queue = state.queue;
    final runtime = state.runtime!;

    _miniProgressTimer?.cancel();
    _miniProgressTimer = null;

    final currentPos = state.position > Duration.zero
        ? state.position
        : runtime.position;
    final updatedPlan = plan.copyWith(
      startPosition: currentPos > Duration.zero
          ? currentPos
          : plan.startPosition,
    );

    if (!kIsWeb && Platform.isWindows && !AppMotion.isTest) {
      closeMiniSilently();
      final payload = PlayerWindowPayload(
        account: account,
        item: item,
        plan: updatedPlan,
        queue: queue,
      );
      unawaited(
        ref.read(playerWindowCoordinatorProvider).openOrSwitch(payload),
      );
      return;
    }

    state = state.copyWith(mode: PlaybackPresentationMode.full);
    final navigator =
        (context != null ? Navigator.maybeOf(context) : null) ??
        EmbyPlayerApp.rootNavigatorKey.currentState;

    navigator?.push<void>(
      Peek3DPageRoute(
        builder: (context) => PlaybackPage(
          account: account,
          item: item,
          plan: updatedPlan,
          queue: queue,
          runtime: runtime,
          isResumingFromMini: true,
        ),
      ),
    );
  }

  Future<void> togglePlayPause() async {
    if (state.mode == PlaybackPresentationMode.window) {
      if (state.playing) {
        await ref.read(playerWindowCoordinatorProvider).pause();
      } else {
        await ref.read(playerWindowCoordinatorProvider).resume();
      }
      return;
    }
    final runtime = state.runtime;
    if (runtime == null) return;
    await runtime.playOrPause();
    final isPlaying = runtime.playing;
    state = state.copyWith(playing: isPlaying);
    if (state.mode == PlaybackPresentationMode.mini) {
      unawaited(_reportMiniProgress(isPlaying ? 'Unpause' : 'Pause'));
    }
    _syncMiniProgressTimer();
  }

  Future<void> seekRelative(Duration delta) async {
    final runtime = state.runtime;
    if (runtime == null) return;
    final current = state.position > Duration.zero
        ? state.position
        : runtime.position;
    final target = current + delta;
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(
        0,
        state.duration.inMilliseconds > 0
            ? state.duration.inMilliseconds
            : target.inMilliseconds,
      ),
    );
    final updatedPositions = Map<String, Duration>.from(state.recentPositions);
    if (state.item != null) {
      updatedPositions[state.item!.id] = clamped;
    }
    state = state.copyWith(
      position: clamped,
      recentPositions: updatedPositions,
    );
    await runtime.seek(clamped);
    if (state.mode == PlaybackPresentationMode.mini) {
      unawaited(_reportMiniProgress('Seek', positionOverride: clamped));
    }
  }

  Future<void> close({bool disposeRuntime = true}) async {
    if (state.mode == PlaybackPresentationMode.window) {
      await ref.read(playerWindowCoordinatorProvider).closeWindow();
      return;
    }
    final runtime = state.runtime;
    final item = state.item;
    final pos =
        (state.position > Duration.zero ? state.position : runtime?.position) ??
        Duration.zero;
    final account = state.account;
    final plan = state.plan;

    _cancelSubscriptions();

    final updatedPositions = Map<String, Duration>.from(state.recentPositions);
    if (item != null && pos > Duration.zero) {
      updatedPositions[item.id] = pos;
      final watchMinutes = (pos.inSeconds / 60).round();
      if (watchMinutes > 0) {
        unawaited(
          ViewingHistoryStore().recordViewing(
            minutes: watchMinutes,
            kind: item.kind.name,
          ),
        );
      }
    }

    // Invalidate media library HTTP cache so subsequent requests get fresh data
    unawaited(ref.read(mediaLibraryProvider).invalidateCache());

    // If closing from floating mini player, report Stopped to Emby with latest position
    if (disposeRuntime &&
        account != null &&
        plan != null &&
        item != null &&
        !item.isLocal &&
        pos > Duration.zero) {
      try {
        final snapshot = PlaybackSessionSnapshot(
          plan: plan,
          position: pos,
          isPaused: true,
          volume: 100,
          playbackRate: 1.0,
        );
        await ref
            .read(playbackServiceProvider)
            .reportStopped(account, snapshot);
      } catch (_) {
        // Safe report
      }
    }

    state = state.copyWith(
      mode: PlaybackPresentationMode.hidden,
      playing: false,
      recentPositions: updatedPositions,
      revision: state.revision + 1,
    );
    _activeRuntime = null;

    if (disposeRuntime && runtime != null) {
      await runtime.pause();
      await runtime.dispose();
    }
  }

  void _syncMiniProgressTimer() {
    _miniProgressTimer?.cancel();
    _miniProgressTimer = null;
    if (state.mode == PlaybackPresentationMode.mini && state.playing) {
      unawaited(_reportMiniProgress('TimeUpdate'));
      _miniProgressTimer = Timer.periodic(
        const Duration(milliseconds: 3500),
        (_) => unawaited(_reportMiniProgress('TimeUpdate')),
      );
    }
  }

  Future<void> _reportMiniProgress(
    String eventName, {
    Duration? positionOverride,
  }) async {
    final account = state.account;
    final plan = state.plan;
    final item = state.item;
    final runtime = state.runtime;
    if (account == null || plan == null || item == null || item.isLocal) return;
    try {
      final currentPos =
          positionOverride ??
          (state.position > Duration.zero
              ? state.position
              : (runtime?.position ?? Duration.zero));
      final snapshot = PlaybackSessionSnapshot(
        plan: plan,
        position: currentPos,
        isPaused: !state.playing,
        volume: 100,
        playbackRate: 1.0,
      );
      await ref
          .read(playbackServiceProvider)
          .reportProgress(account, snapshot, eventName: eventName);
      final updatedPositions = Map<String, Duration>.from(
        state.recentPositions,
      );
      updatedPositions[item.id] = currentPos;
      state = state.copyWith(recentPositions: updatedPositions);
    } catch (_) {
      // Periodic reporting can fail silently
    }
  }

  void _cancelSubscriptions() {
    _miniProgressTimer?.cancel();
    _miniProgressTimer = null;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
  }
}
