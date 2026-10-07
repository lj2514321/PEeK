import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:embyplayer/src/app/theme.dart';

/// The top floating caption bar for the dedicated Player Window.
/// Supports frameless dragging, always-on-top pinning, minimize, fullscreen, and closing.
class PlayerWindowChrome extends StatefulWidget {
  const PlayerWindowChrome({
    super.key,
    required this.title,
    this.subtitle,
    required this.visible,
    this.actions,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final bool visible;
  final List<Widget>? actions;
  final VoidCallback? onClose;

  @override
  State<PlayerWindowChrome> createState() => _PlayerWindowChromeState();
}

class _PlayerWindowChromeState extends State<PlayerWindowChrome>
    with WindowListener {
  bool _isAlwaysOnTop = false;
  bool _isFullScreen = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkInitialState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
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

  Future<void> _checkInitialState() async {
    if (!kIsWeb && Platform.isWindows) {
      try {
        final onTop = await windowManager.isAlwaysOnTop();
        final full = await windowManager.isFullScreen();
        final max = await windowManager.isMaximized();
        if (mounted) {
          setState(() {
            _isAlwaysOnTop = onTop;
            _isFullScreen = full;
            _isMaximized = max;
          });
        }
      } catch (_) {}
    }
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

  Future<void> _toggleFullScreen() async {
    if (!kIsWeb && Platform.isWindows) {
      final next = !_isFullScreen;
      await windowManager.setFullScreen(next);
      if (mounted) {
        setState(() => _isFullScreen = next);
      }
    }
  }

  Future<void> _minimize() async {
    if (!kIsWeb && Platform.isWindows) {
      await windowManager.minimize();
    }
  }

  Future<void> _close() async {
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (!kIsWeb && Platform.isWindows) {
      await windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.85),
                Colors.black.withValues(alpha: 0.0),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: DragToMoveArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.spotlight,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            widget.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.actions != null) ...[
                ...widget.actions!,
                const SizedBox(width: 8),
              ],
              _WindowButton(
                icon: _isAlwaysOnTop
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                tooltip: _isAlwaysOnTop ? '取消置顶' : '置顶窗口',
                active: _isAlwaysOnTop,
                onPressed: _toggleAlwaysOnTop,
              ),
              _WindowButton(
                icon: Icons.remove_rounded,
                tooltip: '最小化',
                onPressed: _minimize,
              ),
              _WindowButton(
                icon: _isMaximized
                    ? Icons.crop_portrait_rounded
                    : Icons.crop_square_rounded,
                tooltip: _isMaximized ? '向下还原' : '最大化',
                onPressed: _toggleMaximize,
              ),
              _WindowButton(
                icon: _isFullScreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                tooltip: _isFullScreen ? '退出全屏' : '全屏',
                onPressed: _toggleFullScreen,
              ),
              _WindowButton(
                icon: Icons.close_rounded,
                tooltip: '关闭播放器',
                isClose: true,
                onPressed: _close,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: isClose
              ? Colors.red.withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 36,
            height: 32,
            child: Icon(
              icon,
              size: 16,
              color: active ? AppColors.spotlight : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
