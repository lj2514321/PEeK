import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:embyplayer/src/app/app_providers.dart';
import 'package:embyplayer/src/core/domain/media_item.dart';
import 'package:embyplayer/src/core/domain/playback_plan.dart';
import 'package:embyplayer/src/core/domain/playback_settings.dart';
import 'package:embyplayer/src/core/domain/server.dart';
import 'package:embyplayer/src/features/player/domain/playback_queue.dart';
import 'package:embyplayer/src/features/player/domain/player_window_payload.dart';
import 'package:embyplayer/src/features/player/presentation/global_playback_coordinator.dart';
import 'package:embyplayer/src/features/player/presentation/playback_runtime.dart';

final playerWindowCoordinatorProvider = Provider<PlayerWindowCoordinator>((
  ref,
) {
  final coordinator = PlayerWindowCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

class PlayerWindowCoordinator {
  PlayerWindowCoordinator(this.ref) {
    _initChannel();
  }

  final Ref ref;
  WindowController? _playerWindow;
  final WindowMethodChannel _channel = const WindowMethodChannel(
    PlayerWindowProtocol.channelName,
    mode: ChannelMode.bidirectional,
  );

  bool get hasActivePlayerWindow => _playerWindow != null;

  void _initChannel() {
    if (!kIsWeb && Platform.isWindows) {
      _channel.setMethodCallHandler(_handlePlayerMethodCall);
    }
  }

  Future<dynamic> _handlePlayerMethodCall(MethodCall call) async {
    switch (call.method) {
      case PlayerWindowProtocol.methodReportProgress:
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final itemId = args['itemId'] as String;
        final posMs = args['positionMs'] as int;
        final durMs = args['durationMs'] as int?;
        final playing = args['playing'] as bool? ?? true;
        ref
            .read(globalPlaybackCoordinatorProvider.notifier)
            .reportOptimisticProgress(
              itemId,
              Duration(milliseconds: posMs),
              duration: durMs != null ? Duration(milliseconds: durMs) : null,
              playing: playing,
            );
        return true;

      case PlayerWindowProtocol.methodReportStateChanged:
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final playing = args['playing'] as bool? ?? false;
        final global = ref.read(globalPlaybackCoordinatorProvider.notifier);
        global.updatePlaybackState(playing: playing);
        return true;

      case PlayerWindowProtocol.methodReportClosed:
        if (call.arguments is Map) {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final itemId = args['itemId'] as String?;
          final posMs = args['positionMs'] as int?;
          if (itemId != null && posMs != null && posMs > 0) {
            ref
                .read(globalPlaybackCoordinatorProvider.notifier)
                .reportOptimisticProgress(
                  itemId,
                  Duration(milliseconds: posMs),
                  playing: false,
                );
          }
        }
        unawaited(ref.read(mediaLibraryProvider).invalidateCache());
        _playerWindow = null;
        ref
            .read(globalPlaybackCoordinatorProvider.notifier)
            .clearActivePlayback();
        return true;

      case PlayerWindowProtocol.methodHandoverToMiniPlayer:
        _playerWindow = null;
        if (call.arguments is Map) {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          await _handleHandoverToMiniPlayer(args);
        }
        return true;

      case PlayerWindowProtocol.methodReportMediaChanged:
        if (call.arguments is Map) {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final itemMap = args['item'] as Map?;
          final planMap = args['plan'] as Map?;
          if (itemMap != null) {
            final item = MediaItem.fromJson(Map<String, dynamic>.from(itemMap));
            final plan = planMap != null
                ? PlaybackPlan.fromJson(Map<String, dynamic>.from(planMap))
                : null;
            ref
                .read(globalPlaybackCoordinatorProvider.notifier)
                .updateActiveItem(item, plan: plan);
          }
        }
        return true;

      default:
        return null;
    }
  }

  Future<void> _handleHandoverToMiniPlayer(Map<String, dynamic> args) async {
    final item = MediaItem.fromJson(
      Map<String, dynamic>.from(args['item'] as Map),
    );
    final account = args['account'] != null
        ? AuthenticatedServer.fromJson(
            Map<String, dynamic>.from(args['account'] as Map),
          )
        : null;
    final plan = PlaybackPlan.fromJson(
      Map<String, dynamic>.from(args['plan'] as Map),
    );
    final queue = args['queue'] != null
        ? PlaybackQueue.fromJson(
            Map<String, dynamic>.from(args['queue'] as Map),
          )
        : null;
    final posMs = args['positionMs'] as int? ?? 0;
    final position = Duration(milliseconds: posMs);
    final playing = args['playing'] as bool? ?? true;
    final decodingModeName = args['hardwareDecodingMode'] as String?;
    final decodingMode = HardwareDecodingMode.values.firstWhere(
      (e) => e.name == decodingModeName,
      orElse: () => HardwareDecodingMode.automatic,
    );

    final updatedPlan = plan.copyWith(
      startPosition: position > Duration.zero ? position : plan.startPosition,
    );

    final runtime = MediaKitPlaybackRuntime(decodingMode: decodingMode);
    await runtime.open(
      updatedPlan,
      play: playing,
      startPosition: position > Duration.zero ? position : null,
    );

    final global = ref.read(globalPlaybackCoordinatorProvider.notifier);
    global.registerActivePlayback(
      account: account,
      item: item,
      plan: updatedPlan,
      queue: queue,
      runtime: runtime,
      initialPosition: position,
    );
    global.minimize();
  }

  Future<void> openOrSwitch(PlayerWindowPayload payload) async {
    if (kIsWeb || !Platform.isWindows) return;

    final global = ref.read(globalPlaybackCoordinatorProvider.notifier);
    global.registerWindowPlayback(
      account: payload.account,
      item: payload.item,
      plan: payload.plan,
      queue: payload.queue,
      initialPosition: payload.plan.startPosition,
    );

    if (_playerWindow == null) {
      try {
        final controller = await WindowController.create(
          WindowConfiguration(arguments: jsonEncode(payload.toJson())),
        );
        _playerWindow = controller;
        await controller.show();
      } catch (e) {
        debugPrint('[PlayerWindowCoordinator] Failed to create window: $e');
      }
    } else {
      try {
        await _channel.invokeMethod(
          PlayerWindowProtocol.methodSwitchMedia,
          payload.toJson(),
        );
        await _playerWindow!.show();
      } catch (e) {
        debugPrint('[PlayerWindowCoordinator] Failed to switch media: $e');
        // If window crashed or closed without notification, recreate it
        try {
          final controller = await WindowController.create(
            WindowConfiguration(arguments: jsonEncode(payload.toJson())),
          );
          _playerWindow = controller;
          await controller.show();
        } catch (_) {}
      }
    }
  }

  Future<void> focusWindow() async {
    if (_playerWindow != null) {
      try {
        await _playerWindow!.show();
        await _channel.invokeMethod(PlayerWindowProtocol.methodFocus);
      } catch (_) {}
    }
  }

  Future<void> pause() async {
    if (_playerWindow != null) {
      try {
        await _channel.invokeMethod(PlayerWindowProtocol.methodPause);
      } catch (_) {}
    }
  }

  Future<void> resume() async {
    if (_playerWindow != null) {
      try {
        await _channel.invokeMethod(PlayerWindowProtocol.methodResume);
      } catch (_) {}
    }
  }

  Future<void> closeWindow() async {
    if (_playerWindow != null) {
      try {
        await _channel.invokeMethod(PlayerWindowProtocol.methodClose);
      } catch (_) {}
      _playerWindow = null;
    }
    ref.read(globalPlaybackCoordinatorProvider.notifier).clearActivePlayback();
  }

  void dispose() {
    if (!kIsWeb && Platform.isWindows) {
      if (_playerWindow != null) {
        unawaited(closeWindow());
      }
      _channel.setMethodCallHandler(null);
    }
  }
}
