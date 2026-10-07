import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:embyplayer/src/app/app.dart';
import 'package:embyplayer/src/core/storage/app_storage_path.dart';
import 'package:embyplayer/src/features/player/domain/player_window_payload.dart';
import 'package:embyplayer/src/features/player/presentation/player_window_app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStoragePath.ensureInitialized();
  MediaKit.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();

    // 1. Direct entrypoint check from desktop_multi_window native arguments
    if (args.isNotEmpty && args.first == 'multi_window' && args.length >= 3) {
      final windowId = args[1];
      final argumentStr = args[2];
      try {
        final payloadMap = jsonDecode(argumentStr) as Map<String, dynamic>;
        final payload = PlayerWindowPayload.fromJson(payloadMap);
        final windowController = WindowController.fromWindowId(windowId);

        const windowOptions = WindowOptions(
          size: Size(1024, 576),
          minimumSize: Size(480, 270),
          center: true,
          backgroundColor: Color(0x00000000),
          title: 'PEeK Player',
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.setAsFrameless();
          await windowManager.setHasShadow(false);
          await windowManager.show();
          await windowManager.focus();
        });

        runApp(PlayerWindowApp(
          windowController: windowController,
          initialPayload: payload,
        ));
        return;
      } catch (e) {
        debugPrint('[main] Failed to launch PlayerWindowApp via entrypoint args: $e');
      }
    }

    try {
      final windowController = await WindowController.fromCurrentEngine();
      if (windowController.arguments.isNotEmpty) {
        final payloadMap =
            jsonDecode(windowController.arguments) as Map<String, dynamic>;
        final payload = PlayerWindowPayload.fromJson(payloadMap);

        const windowOptions = WindowOptions(
          size: Size(1024, 576),
          minimumSize: Size(480, 270),
          center: true,
          backgroundColor: Color(0x00000000),
          title: 'PEeK Player',
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.setAsFrameless();
          await windowManager.setHasShadow(false);
          await windowManager.show();
          await windowManager.focus();
        });

        runApp(PlayerWindowApp(
          windowController: windowController,
          initialPayload: payload,
        ));
        return;
      }
    } catch (_) {
      // Not running in multi-window context or test environment
    }

    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(820, 560),
      center: true,
      backgroundColor: Color(0xFF070810),
      title: 'PEeK',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const ProviderScope(child: EmbyPlayerApp()));
}
