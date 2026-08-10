import 'package:embyplayer/src/app/app_chrome.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/cinematic_scroll_behavior.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:embyplayer/src/features/home/presentation/home_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class EmbyPlayerApp extends StatelessWidget {
  const EmbyPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PEeK',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      scrollBehavior: const CinematicScrollBehavior(),
      builder: (context, child) {
        final content = PeekSmoothScroll(child: child ?? const SizedBox.shrink());
        if (defaultTargetPlatform != TargetPlatform.windows) {
          return content;
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
          child: Stack(
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
    return SizedBox(
      width: AppChrome.windowControlsWidth,
      height: AppChrome.windowControlsHeight,
      child: Row(
        children: [
          WindowCaptionButton.minimize(
            brightness: Brightness.dark,
            onPressed: () => windowManager.minimize(),
          ),
          WindowCaptionButton.maximize(
            brightness: Brightness.dark,
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          WindowCaptionButton.close(
            brightness: Brightness.dark,
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}
