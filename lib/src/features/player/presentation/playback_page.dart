import 'dart:async';

import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/network/network_providers.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PlaybackPage extends ConsumerStatefulWidget {
  const PlaybackPage({
    super.key,
    required this.account,
    required this.item,
    required this.plan,
  });

  final AuthenticatedServer account;
  final MediaItem item;
  final PlaybackPlan plan;

  @override
  ConsumerState<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends ConsumerState<PlaybackPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<String>? _errorSubscription;
  Timer? _progressTimer;
  bool _reportedStarted = false;
  bool _reportedStopped = false;
  bool _playerDisposed = false;
  bool _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _playingSubscription = _player.stream.playing.listen(_playingChanged);
    _completedSubscription = _player.stream.completed.listen((completed) {
      if (completed) _finishCompletedPlayback();
    });
    _errorSubscription = _player.stream.error.listen((message) {
      if (mounted && message.isNotEmpty) setState(() => _error = message);
    });
    Future<void>.microtask(_open);
  }

  Future<void> _open() async {
    try {
      await _player.open(
        Media(
          widget.plan.streamUri.toString(),
          httpHeaders: widget.plan.httpHeaders,
          start: widget.plan.startPosition,
        ),
      );
      await _safeReportStarted();
      _progressTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _safeReportProgress('TimeUpdate'),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '无法打开媒体：$error');
    }
  }

  void _playingChanged(bool playing) {
    if (!_reportedStarted || _closing) return;
    _safeReportProgress(playing ? 'Unpause' : 'Pause');
  }

  Future<void> _safeReportStarted() async {
    try {
      await ref
          .read(playbackServiceProvider)
          .reportStarted(widget.account, _snapshot());
      _reportedStarted = true;
    } catch (_) {
      // Playback remains available even if presence reporting is unavailable.
    }
  }

  Future<void> _safeReportProgress(String eventName) async {
    if (!_reportedStarted || _reportedStopped) return;
    try {
      await ref
          .read(playbackServiceProvider)
          .reportProgress(widget.account, _snapshot(), eventName: eventName);
    } catch (_) {
      // The next periodic check-in can recover from a transient failure.
    }
  }

  Future<void> _safeReportStopped() async {
    if (_reportedStopped || !_reportedStarted) return;
    _reportedStopped = true;
    try {
      await ref
          .read(playbackServiceProvider)
          .reportStopped(widget.account, _snapshot());
    } catch (_) {
      // Closing playback must not be blocked by a reporting failure.
    }
  }

  Future<void> _finishCompletedPlayback() async {
    _progressTimer?.cancel();
    await _safeReportStopped();
  }

  PlaybackSessionSnapshot _snapshot() {
    return PlaybackSessionSnapshot(
      plan: widget.plan,
      position: _player.state.position,
      isPaused: !_player.state.playing,
      volume: _player.state.volume,
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    _progressTimer?.cancel();
    await _safeReportStopped();
    await _disposePlayer();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disposePlayer() async {
    if (_playerDisposed) return;
    _playerDisposed = true;
    await _player.dispose();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    final playingSubscription = _playingSubscription;
    final completedSubscription = _completedSubscription;
    final errorSubscription = _errorSubscription;
    if (playingSubscription != null) unawaited(playingSubscription.cancel());
    if (completedSubscription != null) {
      unawaited(completedSubscription.cancel());
    }
    if (errorSubscription != null) unawaited(errorSubscription.cancel());
    if (!_reportedStopped) unawaited(_safeReportStopped());
    if (!_playerDisposed) unawaited(_disposePlayer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
          child: Focus(
            autofocus: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(controller: _controller),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _PlaybackTopBar(
                    title: widget.item.name,
                    method: widget.plan.method,
                    closing: _closing,
                    onBack: _close,
                  ),
                ),
                if (_error != null)
                  Center(
                    child: _PlaybackError(message: _error!, onBack: _close),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackTopBar extends StatelessWidget {
  const _PlaybackTopBar({
    required this.title,
    required this.method,
    required this.closing,
    required this.onBack,
  });

  final String title;
  final PlaybackMethod method;
  final bool closing;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 24, 34),
          child: Row(
            children: [
              IconButton(
                tooltip: '退出播放（Esc）',
                onPressed: closing ? null : onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  _methodLabel(method),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _methodLabel(PlaybackMethod method) {
    return switch (method) {
      PlaybackMethod.directPlay => 'DIRECT PLAY',
      PlaybackMethod.directStream => 'DIRECT STREAM',
      PlaybackMethod.transcode => 'TRANSCODE',
    };
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 520,
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.14),
            blurRadius: 22,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: onBack, child: const Text('返回详情')),
        ],
      ),
    );
  }
}
