import 'dart:async';

import 'package:flutter/foundation.dart';

class PlaybackSeekFeedbackState {
  const PlaybackSeekFeedbackState({
    required this.deltaSeconds,
    required this.position,
  });

  final int deltaSeconds;
  final Duration position;
}

/// Coordinates short-lived player interaction state outside the widget tree.
///
/// The page supplies guard callbacks because playback, diagnostics, and source
/// changes remain session concerns. This class owns only interaction timers and
/// coalesces repeated keyboard seeks into a single native seek.
class PlaybackInteractionCoordinator {
  PlaybackInteractionCoordinator({
    required this.canShowControls,
    required this.canAutoHideControls,
    required this.isActive,
    required this.onControlsShown,
    required this.onControlsVisibilityChanged,
    this.controlsHideDelay = const Duration(seconds: 3),
    this.seekCommitDelay = const Duration(milliseconds: 110),
    this.seekFeedbackDuration = const Duration(milliseconds: 850),
  });

  final bool Function() canShowControls;
  final bool Function() canAutoHideControls;
  final bool Function() isActive;
  final VoidCallback onControlsShown;
  final VoidCallback onControlsVisibilityChanged;
  final Duration controlsHideDelay;
  final Duration seekCommitDelay;
  final Duration seekFeedbackDuration;

  final ValueNotifier<PlaybackSeekFeedbackState?> seekFeedback = ValueNotifier(
    null,
  );

  Timer? _controlsTimer;
  Timer? _seekCommitTimer;
  Timer? _seekFeedbackTimer;
  Duration? _pendingSeekTarget;
  Future<void> Function(Duration target)? _commitSeek;
  Future<void> Function()? _afterSeekCommitted;
  bool _seekCommitRunning = false;
  bool _controlsVisible = true;
  bool _disposed = false;

  bool get controlsVisible => _controlsVisible;
  Duration? get pendingSeekTarget => _pendingSeekTarget;

  void showControls() {
    if (_disposed || !isActive() || !canShowControls()) return;
    onControlsShown();
    _setControlsVisible(true);
    scheduleControlsHide();
  }

  void hideControls({bool force = false}) {
    cancelControlsHide();
    if (_disposed || !isActive() || !canShowControls()) return;
    if (!force && !canAutoHideControls()) return;
    _setControlsVisible(false);
  }

  void toggleControls({required bool playing}) {
    if (_controlsVisible && playing) {
      hideControls(force: true);
    } else {
      showControls();
    }
  }

  void scheduleControlsHide() {
    cancelControlsHide();
    if (_disposed || !canAutoHideControls()) return;
    _controlsTimer = Timer(controlsHideDelay, () {
      if (!_disposed && isActive() && canAutoHideControls()) {
        hideControls(force: true);
      }
    });
  }

  void cancelControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = null;
  }

  Duration queueRelativeSeek({
    required Duration base,
    required Duration offset,
    required Duration duration,
    required Future<void> Function(Duration target) commit,
    required Future<void> Function() afterCommitted,
  }) {
    final target = _clampPosition(base + offset, duration);
    _pendingSeekTarget = target;
    _commitSeek = commit;
    _afterSeekCommitted = afterCommitted;

    final current = seekFeedback.value;
    seekFeedback.value = PlaybackSeekFeedbackState(
      deltaSeconds: (current?.deltaSeconds ?? 0) + offset.inSeconds,
      position: target,
    );
    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(seekFeedbackDuration, () {
      if (!_disposed) seekFeedback.value = null;
    });

    _seekCommitTimer?.cancel();
    _seekCommitTimer = Timer(
      seekCommitDelay,
      () => unawaited(_commitPendingSeek()),
    );
    return target;
  }

  void cancelPendingSeek() {
    _seekCommitTimer?.cancel();
    _seekCommitTimer = null;
    _pendingSeekTarget = null;
  }

  Future<void> _commitPendingSeek() async {
    if (_disposed || _seekCommitRunning || !isActive()) return;
    final commit = _commitSeek;
    final afterCommitted = _afterSeekCommitted;
    if (commit == null || afterCommitted == null) return;

    _seekCommitRunning = true;
    var changed = false;
    try {
      while (!_disposed && isActive()) {
        final target = _pendingSeekTarget;
        if (target == null) break;
        _pendingSeekTarget = null;
        await commit(target);
        changed = true;
      }
      if (changed && !_disposed && isActive()) {
        await afterCommitted();
      }
    } finally {
      _seekCommitRunning = false;
      if (_pendingSeekTarget != null && !_disposed && isActive()) {
        unawaited(_commitPendingSeek());
      }
    }
  }

  void _setControlsVisible(bool value) {
    if (_controlsVisible == value) return;
    _controlsVisible = value;
    onControlsVisibilityChanged();
  }

  Duration _clampPosition(Duration value, Duration duration) {
    if (value < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && value > duration) return duration;
    return value;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelControlsHide();
    cancelPendingSeek();
    _seekFeedbackTimer?.cancel();
    seekFeedback.dispose();
  }
}
