import 'dart:async';

import 'package:embyplayer/src/app/app.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/features/analytics/data/viewing_history_store.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_queue.dart';
import 'package:embyplayer/src/features/player/presentation/playback_page.dart';
import 'package:embyplayer/src/features/player/presentation/playback_runtime.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PlaybackPresentationMode {
  hidden,
  mini,
  full,
}

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

  void registerActivePlayback({
    required AuthenticatedServer? account,
    required MediaItem item,
    required PlaybackPlan plan,
    PlaybackQueue? queue,
    required PlaybackRuntime runtime,
  }) {
    _cancelSubscriptions();
    _activeRuntime = runtime;

    _subscriptions.add(
      runtime.playingStream.listen((playing) {
        state = state.copyWith(playing: playing);
        _syncMiniProgressTimer();
      }),
    );
    _subscriptions.add(
      runtime.positionStream.listen((position) {
        if (position > Duration.zero || state.position == Duration.zero) {
          state = state.copyWith(position: position);
        }
      }),
    );
    _subscriptions.add(
      runtime.durationStream.listen((duration) {
        state = state.copyWith(duration: duration);
      }),
    );

    state = GlobalPlaybackState(
      mode: PlaybackPresentationMode.full,
      account: account,
      item: item,
      plan: plan,
      queue: queue,
      runtime: runtime,
      playing: runtime.playing,
      position: runtime.position,
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
    if (state.runtime == null || state.item == null || state.plan == null) return;
    final item = state.item!;
    final account = state.account;
    final plan = state.plan!;
    final queue = state.queue;
    final runtime = state.runtime!;

    _miniProgressTimer?.cancel();
    _miniProgressTimer = null;
    state = state.copyWith(mode: PlaybackPresentationMode.full);

    final currentPos = state.position > Duration.zero
        ? state.position
        : runtime.position;
    final updatedPlan = plan.copyWith(
      startPosition: currentPos > Duration.zero ? currentPos : plan.startPosition,
    );

    final navigator = (context != null ? Navigator.maybeOf(context) : null) ??
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
    final runtime = state.runtime;
    if (runtime == null) return;
    await runtime.playOrPause();
    _syncMiniProgressTimer();
  }

  Future<void> seekRelative(Duration delta) async {
    final runtime = state.runtime;
    if (runtime == null) return;
    final target = state.position + delta;
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(
        0,
        state.duration.inMilliseconds > 0
            ? state.duration.inMilliseconds
            : target.inMilliseconds,
      ),
    );
    await runtime.seek(clamped);
    if (state.mode == PlaybackPresentationMode.mini) {
      _reportMiniProgress('Seek');
    }
  }

  Future<void> close({bool disposeRuntime = true}) async {
    final runtime = state.runtime;
    final item = state.item;
    final pos = runtime?.position ?? state.position;
    final account = state.account;
    final plan = state.plan;

    _cancelSubscriptions();

    if (item != null) {
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
        await ref.read(playbackServiceProvider).reportStopped(account, snapshot);
      } catch (_) {
        // Safe report
      }
    }

    state = const GlobalPlaybackState(mode: PlaybackPresentationMode.hidden);
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
      _miniProgressTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_reportMiniProgress('TimeUpdate')),
      );
    }
  }

  Future<void> _reportMiniProgress(String eventName) async {
    final account = state.account;
    final plan = state.plan;
    final item = state.item;
    final runtime = state.runtime;
    if (account == null || plan == null || item == null || item.isLocal) return;
    try {
      final currentPos = runtime?.position ?? state.position;
      final snapshot = PlaybackSessionSnapshot(
        plan: plan,
        position: currentPos,
        isPaused: !state.playing,
        volume: 100,
        playbackRate: 1.0,
      );
      await ref.read(playbackServiceProvider).reportProgress(
            account,
            snapshot,
            eventName: eventName,
          );
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
