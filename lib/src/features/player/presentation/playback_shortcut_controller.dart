import 'package:flutter/services.dart';

/// Controller handling keyboard shortcuts for playback controls.
class PlaybackShortcutController {
  const PlaybackShortcutController();

  bool handleKeyEvent({
    required KeyEvent event,
    required VoidCallback onTogglePlayPause,
    required VoidCallback onSeekForward,
    required VoidCallback onSeekBackward,
    required VoidCallback onVolumeUp,
    required VoidCallback onVolumeDown,
    required VoidCallback onToggleMute,
    required VoidCallback onToggleFullScreen,
    required VoidCallback onToggleDiagnostics,
    required VoidCallback onBackPressed,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }

    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;

    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyD) {
      onToggleDiagnostics();
      return true;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        onTogglePlayPause();
        return true;
      case LogicalKeyboardKey.arrowLeft:
        onSeekBackward();
        return true;
      case LogicalKeyboardKey.arrowRight:
        onSeekForward();
        return true;
      case LogicalKeyboardKey.arrowUp:
        onVolumeUp();
        return true;
      case LogicalKeyboardKey.arrowDown:
        onVolumeDown();
        return true;
      case LogicalKeyboardKey.keyM:
        onToggleMute();
        return true;
      case LogicalKeyboardKey.keyF:
        onToggleFullScreen();
        return true;
      case LogicalKeyboardKey.escape:
        onBackPressed();
        return true;
      default:
        return false;
    }
  }
}
