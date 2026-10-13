import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:embyplayer/src/app/app.dart';
import 'package:embyplayer/src/core/storage/app_storage_path.dart';
import 'package:embyplayer/src/features/player/domain/player_window_payload.dart';
import 'package:embyplayer/src/features/player/presentation/player_window_app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

/// Warms up Skia rasterizer shader pipelines (blur, gradients, 3D matrices)
/// before the primary UI tree mounts, eliminating Skia JIT shader compilation
/// hitching during initial page load animations on desktop.
void _warmupGraphicsPipeline() {
  try {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 256 * 1024 * 1024;
    PaintingBinding.instance.imageCache.maximumSize = 1200;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 100, 100));

    // 1. Skia blur shader warm-up
    final paintBlur = Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: 32,
        sigmaY: 32,
        tileMode: TileMode.decal,
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100), paintBlur);

    // 2. Skia linear & radial gradient shaders warm-up
    final paintGrad = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(100, 100), const [
        Color(0xFF6B421B),
        Color(0xFF101729),
      ]);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 100, 100),
        const Radius.circular(16),
      ),
      paintGrad,
    );

    // 3. Skia 3D perspective transform matrix warm-up
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateX(0.04)
      ..rotateY(0.04);
    canvas.transform(matrix.storage);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 50, 50),
      Paint()..color = const Color(0x1AFFFFFF),
    );

    final picture = recorder.endRecording();
    final image = picture.toImageSync(100, 100);
    image.dispose();
    picture.dispose();
  } catch (_) {
    // Non-fatal if headless or test environment
  }
}

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  _warmupGraphicsPipeline();
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
        await windowManager.waitUntilReadyToShow(windowOptions);
        await windowManager.setAsFrameless();
        await windowManager.setHasShadow(false);
        await windowManager.show();
        await windowManager.focus();

        runApp(
          PlayerWindowApp(
            windowController: windowController,
            initialPayload: payload,
          ),
        );
        return;
      } catch (e) {
        debugPrint(
          '[main] Failed to launch PlayerWindowApp via entrypoint args: $e',
        );
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
        await windowManager.waitUntilReadyToShow(windowOptions);
        await windowManager.setAsFrameless();
        await windowManager.setHasShadow(false);
        await windowManager.show();
        await windowManager.focus();

        runApp(
          PlayerWindowApp(
            windowController: windowController,
            initialPayload: payload,
          ),
        );
        return;
      }
    } catch (_) {
      // Not running in multi-window context or test environment
    }

    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(820, 560),
      center: true,
      backgroundColor: Color(0x00000000),
      title: 'PEeK',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions);
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
  }

  runApp(const ProviderScope(child: EmbyPlayerApp()));
}
