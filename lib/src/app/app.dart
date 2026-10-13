import 'dart:ui';

import 'package:embyplayer/src/app/app_chrome.dart';
import 'package:embyplayer/src/app/peek_warmup_gate.dart';
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
        final content = PeekSmoothScroll(
          child: child ?? const SizedBox.shrink(),
        );
        if (defaultTargetPlatform != TargetPlatform.windows) {
          return Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Stack(
                  fit: StackFit.expand,
                  children: [content, const FloatingMiniPlayer()],
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
            return ClipRRect(
              borderRadius: AppRadius.borderRadius,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.borderRadius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 1.0,
                  ),
                ),
                child: ColoredBox(
                  color: AppColors.canvas,
                  child: _FramelessWindowSurface(child: content),
                ),
              ),
            );
          },
        );
      },
      home: const PeekWarmupGate(child: HomeShell()),
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
                      Positioned(
                        top: 0,
                        left: 0,
                        right: AppChrome.windowControlsWidth + 8,
                        height: 12,
                        child: const DragToMoveArea(child: SizedBox.expand()),
                      ),
                    const Positioned(
                      top: 0,
                      right: 0,
                      child: _WindowControls(),
                    ),
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: AppRadius.borderRadius,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.32),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _WindowCaptionAction(
                  icon: Icons.remove_rounded,
                  tooltip: '最小化',
                  onTap: () => windowManager.minimize(),
                ),
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
                _WindowCaptionAction(
                  icon: Icons.close_rounded,
                  tooltip: '关闭',
                  isClose: true,
                  onTap: () => windowManager.close(),
                ),
              ],
            ),
          ),
        ),
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
        ? const Color(0xFFE81123).withValues(alpha: 0.88)
        : Colors.white.withValues(alpha: 0.22);
    final iconColor = _hovered
        ? Colors.white
        : (widget.isClose
              ? Colors.white.withValues(alpha: 0.90)
              : Colors.white.withValues(alpha: 0.78));

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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _hovered ? hoverColor : Colors.transparent,
              borderRadius: AppRadius.borderRadius,
              border: _hovered
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.36),
                      width: 1,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: iconColor),
          ),
        ),
      ),
    );
  }
}
