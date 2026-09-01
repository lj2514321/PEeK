import 'package:embyplayer/src/app/app_chrome.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/cinematic_scroll_behavior.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/home/presentation/home_shell.dart';
import 'package:embyplayer/src/features/player/presentation/floating_mini_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class EmbyPlayerApp extends StatelessWidget {
  const EmbyPlayerApp({super.key});

  static final rootNavigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'PEeK',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      scrollBehavior: const CinematicScrollBehavior(),
      builder: (context, child) {
        final content = PeekSmoothScroll(child: child ?? const SizedBox.shrink());
        if (defaultTargetPlatform != TargetPlatform.windows) {
          return Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Stack(
                  fit: StackFit.expand,
                  children: [
                    content,
                    const FloatingMiniPlayer(),
                  ],
                ),
              ),
            ],
          );
        }
        return ValueListenableBuilder<bool>(
          valueListenable: AppChrome.immersive,
          builder: (context, immersive, _) {
            if (immersive) {
              return ColoredBox(color: AppColors.canvas, child: content);
            }
            return ColoredBox(
              color: AppColors.canvas,
              child: _FramelessWindowSurface(child: content),
            );
          },
        );
      },
      home: const HomeShell(),
    );
  }
}

class _FramelessWindowSurface extends StatelessWidget {
  const _FramelessWindowSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowDragArea =
            constraints.maxWidth > AppChrome.windowControlsWidth + 320;
        return DragToResizeArea(
          resizeEdgeSize: 5,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Stack(
                  fit: StackFit.expand,
                  children: [
                    child,
                    if (canShowDragArea)
                      const Positioned(
                        top: 0,
                        left: 260,
                        right: AppChrome.windowControlsWidth,
                        height: AppChrome.windowControlsHeight,
                        child: DragToMoveArea(child: SizedBox.expand()),
                      ),
                    const Positioned(top: 0, right: 0, child: _WindowControls()),
                    const FloatingMiniPlayer(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppChrome.windowControlsWidth,
      height: AppChrome.windowControlsHeight,
      padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _WindowCaptionAction(
            icon: Icons.remove_rounded,
            tooltip: '最小化',
            onTap: () => windowManager.minimize(),
          ),
          const SizedBox(width: 2),
          _WindowCaptionAction(
            icon: Icons.crop_square_rounded,
            tooltip: '最大化/还原',
            onTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          const SizedBox(width: 2),
          _WindowCaptionAction(
            icon: Icons.close_rounded,
            tooltip: '关闭',
            isClose: true,
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _WindowCaptionAction extends StatefulWidget {
  const _WindowCaptionAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isClose;

  @override
  State<_WindowCaptionAction> createState() => _WindowCaptionActionState();
}

class _WindowCaptionActionState extends State<_WindowCaptionAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isClose
        ? const Color(0xFFE81123)
        : Colors.white.withValues(alpha: 0.12);
    final iconColor = _hovered
        ? Colors.white
        : (widget.isClose
            ? Colors.white.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.70));

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 38,
            height: 28,
            decoration: BoxDecoration(
              color: _hovered ? hoverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 15,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
