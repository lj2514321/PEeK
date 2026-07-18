import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/app_chrome.dart';
import 'package:embyplayer/src/app/theme.dart';
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
      builder: (context, child) {
        if (defaultTargetPlatform != TargetPlatform.windows) {
          return child ?? const SizedBox.shrink();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: AppChrome.immersive,
          builder: (context, immersive, _) {
            final content = child ?? const SizedBox.shrink();
            if (immersive) {
              return ColoredBox(color: AppColors.canvas, child: content);
            }
            return ColoredBox(
              color: AppColors.canvas,
              child: Column(
                children: [
                  GlassSurface(
                    radius: 0,
                    blur: 22,
                    tint: AppColors.glassStrong,
                    child: SizedBox(
                      height: 38,
                      child: Row(
                        children: [
                          Expanded(
                            child: DragToMoveArea(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 14),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 17,
                                      color: AppColors.spotlight,
                                    ),
                                    const SizedBox(width: 7),
                                    const Flexible(
                                      child: Text(
                                        'PEeK  ·  PRIVATE CINEMA',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.7,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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
                    ),
                  ),
                  Expanded(child: content),
                ],
              ),
            );
          },
        );
      },
      home: const HomeShell(),
    );
  }
}
