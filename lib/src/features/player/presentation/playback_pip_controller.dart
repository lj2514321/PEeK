import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

class WindowPipController {
  WindowPipController._();

  static final WindowPipController instance = WindowPipController._();

  bool _isPip = false;
  Rect? _savedBounds;
  bool _wasMaximized = false;

  bool get isPip => _isPip;

  Future<bool> enterPip({Size pipSize = const Size(480, 270)}) async {
    if (defaultTargetPlatform != TargetPlatform.windows &&
        defaultTargetPlatform != TargetPlatform.macOS &&
        defaultTargetPlatform != TargetPlatform.linux) {
      return false;
    }
    if (_isPip) return true;
    try {
      _wasMaximized = await windowManager.isMaximized();
      _savedBounds = await windowManager.getBounds();
      if (_wasMaximized) {
        await windowManager.unmaximize();
      }
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setMinimumSize(const Size(320, 180));
      await windowManager.setSize(pipSize);
      _isPip = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> exitPip() async {
    if (defaultTargetPlatform != TargetPlatform.windows &&
        defaultTargetPlatform != TargetPlatform.macOS &&
        defaultTargetPlatform != TargetPlatform.linux) {
      _isPip = false;
      return true;
    }
    if (!_isPip) return true;
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(480, 270));
      if (_wasMaximized) {
        await windowManager.maximize();
      } else if (_savedBounds != null &&
          _savedBounds!.width >= 480 &&
          _savedBounds!.height >= 270) {
        await windowManager.setBounds(_savedBounds!);
      } else {
        await windowManager.setSize(const Size(1024, 576));
      }
      _savedBounds = null;
      _wasMaximized = false;
      _isPip = false;
      return true;
    } catch (_) {
      _isPip = false;
      return false;
    }
  }

  Future<bool> togglePip({Size pipSize = const Size(480, 270)}) async {
    if (_isPip) {
      return exitPip();
    } else {
      return enterPip(pipSize: pipSize);
    }
  }
}
