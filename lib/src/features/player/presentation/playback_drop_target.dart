import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlaybackDropTarget extends StatefulWidget {
  const PlaybackDropTarget({
    super.key,
    required this.child,
    required this.onSubtitleDropped,
  });

  final Widget child;
  final ValueChanged<File> onSubtitleDropped;

  static const supportedExtensions = {'.srt', '.ass', '.vtt', '.sub', '.lrc'};

  @override
  State<PlaybackDropTarget> createState() => _PlaybackDropTargetState();
}

class _PlaybackDropTargetState extends State<PlaybackDropTarget> {
  bool _dragging = false;

  bool _isSubtitleFile(String path) {
    final lower = path.toLowerCase();
    return PlaybackDropTarget.supportedExtensions.any(lower.endsWith);
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return widget.child;
    }
    return DropTarget(
      onDragEntered: (_) {
        setState(() => _dragging = true);
      },
      onDragExited: (_) {
        if (_dragging) setState(() => _dragging = false);
      },
      onDragDone: (details) {
        setState(() => _dragging = false);
        for (final file in details.files) {
          if (_isSubtitleFile(file.path)) {
            widget.onSubtitleDropped(File(file.path));
            break;
          }
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.72),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    decoration: AppGlass.decoration(radius: 20, selected: true),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.subtitles_rounded,
                          size: 56,
                          color: AppColors.spotlight,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '释放以加载此字幕文件',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '支持 .srt / .ass / .vtt / .sub 格式',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
