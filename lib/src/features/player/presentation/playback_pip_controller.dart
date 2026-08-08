import 'dart:ui';

import 'package:window_manager/window_manager.dart';

class WindowPipController {
  WindowPipController._();

  static final WindowPipController instance = WindowPipController._();

  bool _isPip = false;
  Rect? _savedBounds;

  bool get isPip => _isPip;

  Future<bool> enterPip({Size pipSize = const Size(480, 270)}) async {
    if (_isPip) return true;
    try {
      _savedBounds = await windowManager.getBounds();
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
    if (!_isPip) return true;
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(800, 500));
      if (_savedBounds != null) {
        await windowManager.setBounds(_savedBounds!);
        _savedBounds = null;
      } else {
        await windowManager.setSize(const Size(1280, 720));
      }
      _isPip = false;
      return true;
    } catch (_) {
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
