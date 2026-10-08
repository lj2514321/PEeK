import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/domain/media_item.dart';
import 'package:embyplayer/src/core/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/player_window_payload.dart';
import 'package:embyplayer/src/features/player/presentation/playback_page.dart';

class PlayerWindowApp extends StatelessWidget {
  const PlayerWindowApp({
    super.key,
    required this.windowController,
    required this.initialPayload,
  });

  final WindowController windowController;
  final PlayerWindowPayload initialPayload;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: initialPayload.item.name,
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: AppTheme.dark(),
        theme: AppTheme.dark(),
        home: PlayerWindowPage(
          windowController: windowController,
          initialPayload: initialPayload,
        ),
      ),
    );
  }
}

class PlayerWindowPage extends StatefulWidget {
  const PlayerWindowPage({
    super.key,
    required this.windowController,
    required this.initialPayload,
  });

  final WindowController windowController;
  final PlayerWindowPayload initialPayload;

  @override
  State<PlayerWindowPage> createState() => _PlayerWindowPageState();
}

class _PlayerWindowPageState extends State<PlayerWindowPage>
    with WindowListener {
  late PlayerWindowPayload _payload = widget.initialPayload;
  GlobalKey<PlaybackPageState> _playbackKey = GlobalKey<PlaybackPageState>();
  bool _isClosing = false;
  bool _isMaximized = false;
  bool _isFullScreen = false;
  bool _isAlwaysOnTop = false;

  final WindowMethodChannel _channel = const WindowMethodChannel(
    PlayerWindowProtocol.channelName,
    mode: ChannelMode.bidirectional,
  );

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    if (!kIsWeb && Platform.isWindows) {
      windowManager.setPreventClose(true);
      _checkInitialWindowState();
    }
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _checkInitialWindowState() async {
    try {
      final isMax = await windowManager.isMaximized();
      final isFull = await windowManager.isFullScreen();
      final isTop = await windowManager.isAlwaysOnTop();
      if (mounted) {
        setState(() {
          _isMaximized = isMax;
          _isFullScreen = isFull;
          _isAlwaysOnTop = isTop;
        });
      }
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  @override
  void onWindowClose() async {
    await _requestClose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case PlayerWindowProtocol.methodSwitchMedia:
        final raw = call.arguments;
        if (raw is Map) {
          final payload = PlayerWindowPayload.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (mounted) {
            setState(() {
              _payload = payload;
              _playbackKey = GlobalKey<PlaybackPageState>();
            });
          }
        }
        return true;

      case PlayerWindowProtocol.methodPause:
        await _playbackKey.currentState?.pause();
        return true;

      case PlayerWindowProtocol.methodResume:
        await _playbackKey.currentState?.resume();
        return true;

      case PlayerWindowProtocol.methodSeek:
        final rawPos = call.arguments;
        if (rawPos is int) {
          await _playbackKey.currentState?.seek(Duration(milliseconds: rawPos));
        } else if (rawPos is Map && rawPos['positionMs'] is int) {
          await _playbackKey.currentState?.seek(
            Duration(milliseconds: rawPos['positionMs'] as int),
          );
        }
        return true;

      case PlayerWindowProtocol.methodFocus:
        await windowManager.show();
        await windowManager.focus();
        return true;

      case PlayerWindowProtocol.methodClose:
        await _requestClose();
        return true;

      default:
        return null;
    }
  }

  Future<void> _requestClose() async {
    if (_isClosing) return;
    _isClosing = true;

    // Immediately remove window listener to avoid recursive or intercepted close events
    windowManager.removeListener(this);

    // 1. Immediately hide window for instant visual feedback
    if (!kIsWeb && Platform.isWindows) {
      try {
        await windowManager.hide();
      } catch (_) {}
    }

    // 2. Shut down playback gracefully (reports stopped to Emby, stops media_kit, records viewing history)
    final posBeforeClose =
        _playbackKey.currentState?.currentPosition ?? Duration.zero;
    try {
      await _playbackKey.currentState?.close();
    } catch (e) {
      debugPrint('[PlayerWindow] Error during playback shutdown: $e');
    }
    final posAfterClose =
        _playbackKey.currentState?.currentPosition ?? Duration.zero;
    final finalPos =
        posAfterClose > Duration.zero ? posAfterClose : posBeforeClose;

    // 3. Notify main window coordinator
    try {
      final currentItemId =
          _playbackKey.currentState?.currentItem.id ?? _payload.item.id;
      await _channel.invokeMethod(
        PlayerWindowProtocol.methodReportClosed,
        {
          'itemId': currentItemId,
          'positionMs': finalPos.inMilliseconds,
        },
      );
    } catch (_) {}

    // 4. Clear preventClose so WM_CLOSE is handled normally by Windows, then destroy native subwindow
    if (!kIsWeb && Platform.isWindows) {
      try {
        await windowManager.setPreventClose(false);
      } catch (_) {}

      try {
        await const MethodChannel('peek/subwindow').invokeMethod('destroyWindow');
      } catch (_) {
        try {
          await windowManager.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _handoverToMiniPlayer() async {
    if (_isClosing) return;
    _isClosing = true;

    windowManager.removeListener(this);

    // 1. Immediately hide window for instant visual feedback
    if (!kIsWeb && Platform.isWindows) {
      try {
        await windowManager.hide();
      } catch (_) {}
    }

    // 2. Capture latest playback state
    final currentPos =
        _playbackKey.currentState?.currentPosition ?? Duration.zero;
    final currentItem =
        _playbackKey.currentState?.currentItem ?? _payload.item;
    final currentPlan =
        _playbackKey.currentState?.currentPlan ?? _payload.plan;
    final currentQueue =
        _playbackKey.currentState?.currentQueue ?? _payload.queue;
    final isPlaying = _playbackKey.currentState?.isPlaying ?? true;
    final currentBitrate =
        _playbackKey.currentState?.maxStreamingBitrate ??
        _payload.maxStreamingBitrate;
    final currentSubPref =
        _playbackKey.currentState?.subtitlePreferences ??
        _payload.subtitlePreferences;
    final currentSkipPref =
        _playbackKey.currentState?.skipIntroPreferences ??
        _payload.skipIntroPreferences;
    final currentDanmakuPref =
        _playbackKey.currentState?.danmakuPreferences ??
        _payload.danmakuPreferences;

    // 3. Pause sub-window player immediately
    try {
      await _playbackKey.currentState?.pause();
    } catch (_) {}

    // 4. Notify main window coordinator to adopt playback in mini player
    try {
      await _channel.invokeMethod(
        PlayerWindowProtocol.methodHandoverToMiniPlayer,
        {
          'account': _payload.account?.toJson(),
          'item': currentItem.toJson(),
          'plan': currentPlan.toJson(),
          'queue': currentQueue?.toJson(),
          'positionMs': currentPos.inMilliseconds,
          'playing': isPlaying,
          'hardwareDecodingMode': _payload.hardwareDecodingMode.name,
          'maxStreamingBitrate': currentBitrate.name,
          'subtitlePreferences': currentSubPref.toJson(),
          'skipIntroPreferences': currentSkipPref.toJson(),
          'danmakuPreferences': currentDanmakuPref.toJson(),
        },
      );
    } catch (e) {
      debugPrint('[PlayerWindow] Error during handover to mini player: $e');
    }

    // 5. Dispose sub-window player and destroy native subwindow
    try {
      await _playbackKey.currentState?.disposePlayer();
    } catch (_) {}

    if (!kIsWeb && Platform.isWindows) {
      try {
        await windowManager.setPreventClose(false);
      } catch (_) {}

      try {
        await const MethodChannel('peek/subwindow').invokeMethod('destroyWindow');
      } catch (_) {
        try {
          await windowManager.close();
        } catch (_) {}
      }
    }
  }

  void _onItemChanged(MediaItem item, PlaybackPlan plan) {
    if (mounted) {
      setState(() {
        _payload = _payload.copyWith(item: item, plan: plan);
      });
    }
    _channel.invokeMethod(
      PlayerWindowProtocol.methodReportMediaChanged,
      {
        'item': item.toJson(),
        'plan': plan.toJson(),
      },
    );
  }

  Future<void> _toggleAlwaysOnTop() async {
    if (!kIsWeb && Platform.isWindows) {
      final next = !_isAlwaysOnTop;
      await windowManager.setAlwaysOnTop(next);
      if (mounted) {
        setState(() => _isAlwaysOnTop = next);
      }
    }
  }

  Future<void> _toggleMaximize() async {
    if (!kIsWeb && Platform.isWindows) {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    }
  }

  void _onProgressUpdated(Duration position, Duration duration, bool playing) {
    final currentItemId =
        _playbackKey.currentState?.currentItem.id ?? _payload.item.id;
    _channel.invokeMethod(
      PlayerWindowProtocol.methodReportProgress,
      {
        'itemId': currentItemId,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'playing': playing,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFloating = !_isMaximized && !_isFullScreen;
    final radius = isFloating ? 12.0 : 0.0;
    final borderRadius = BorderRadius.circular(radius);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DragToResizeArea(
        resizeEdgeSize: isFloating ? 6 : 0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: borderRadius,
            border: isFloating
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                    width: 1.0,
                  )
                : null,
            boxShadow: isFloating
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.60),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: PlaybackPage(
              key: _playbackKey,
              account: _payload.account,
              item: _payload.item,
              plan: _payload.plan,
              queue: _payload.queue,
              hardwareDecodingMode: _payload.hardwareDecodingMode,
              maxStreamingBitrate: _payload.maxStreamingBitrate,
              subtitlePreferences: _payload.subtitlePreferences,
              skipIntroPreferences: _payload.skipIntroPreferences,
              danmakuPreferences: _payload.danmakuPreferences,
              enableMiniPlayer: true,
              onProgressUpdated: _onProgressUpdated,
              onItemChanged: _onItemChanged,
              onWindowClosed: _requestClose,
              onMinimizeToMini: _handoverToMiniPlayer,
              onMinimize: () => windowManager.minimize(),
              onToggleMaximize: _toggleMaximize,
              onToggleAlwaysOnTop: _toggleAlwaysOnTop,
              isAlwaysOnTop: _isAlwaysOnTop,
              isMaximized: _isMaximized,
            ),
          ),
        ),
      ),
    );
  }
}
