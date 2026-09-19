import 'package:embyplayer/src/features/danmaku/data/dandanplay_service.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:flutter/material.dart';

class DanmakuOverlay extends StatelessWidget {
  const DanmakuOverlay({
    super.key,
    required this.items,
    required this.position,
    this.preferences = const DanmakuPreferences(),
    this.enabled,
    this.opacity,
    this.fontSize,
  });

  final List<DanmakuItem> items;
  final Duration position;
  final DanmakuPreferences preferences;
  final bool? enabled;
  final double? opacity;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled ?? preferences.enabled;
    if (!isEnabled || items.isEmpty) return const SizedBox.shrink();

    final effectiveOpacity = opacity ?? preferences.opacity;
    final effectiveFontSize = fontSize ?? preferences.fontSize;

    final currentSec =
        (position.inMilliseconds + preferences.offsetMilliseconds) / 1000.0;
    final blocked = preferences.blockedKeywords;

    // Show items active within [currentSec - 6.0, currentSec]
    final activeItems = items.where((item) {
      if (blocked.isNotEmpty &&
          blocked.any((kw) => kw.isNotEmpty && item.text.contains(kw))) {
        return false;
      }
      if (item.type == 1 && !preferences.allowScroll) return false;
      if (item.type == 5 && !preferences.allowTop) return false;
      if (item.type == 4 && !preferences.allowBottom) return false;

      final delta = currentSec - item.timeSeconds;
      return delta >= 0.0 && delta <= 6.0;
    }).toList(growable: false);

    if (activeItems.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: Opacity(
        opacity: effectiveOpacity.clamp(0.1, 1.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final maxHeightAllowed = preferences.preventSubtitleOverlap
                ? (height * 0.78).clamp(80.0, height)
                : height;
            final displayHeight =
                (height * preferences.displayArea.clamp(0.15, 1.0))
                    .clamp(0.0, maxHeightAllowed);
            final trackCount =
                (displayHeight / (effectiveFontSize * 1.8)).floor().clamp(2, 16);
            final trackHeight = displayHeight / trackCount;

            return Stack(
              children: [
                for (var i = 0; i < activeItems.length; i++) ...[
                  builderDanmakuItem(
                    context,
                    item: activeItems[i],
                    index: i,
                    currentSec: currentSec,
                    width: width,
                    trackHeight: trackHeight,
                    trackCount: trackCount,
                    fontSize: effectiveFontSize,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget builderDanmakuItem(
    BuildContext context, {
    required DanmakuItem item,
    required int index,
    required double currentSec,
    required double width,
    required double trackHeight,
    int trackCount = 6,
    double fontSize = 16.0,
  }) {
    final progress = (currentSec - item.timeSeconds) / 6.0;
    final trackIndex = index % trackCount;
    final top = trackIndex * trackHeight;
    final left = width - (progress * (width + 300));

    final colorValue =
        item.color == 16777215 ? 0xFFFFFFFF : item.color | 0xFF000000;

    return Positioned(
      top: top,
      left: left,
      child: Text(
        item.text,
        maxLines: 1,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: Color(colorValue),
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(blurRadius: 4, color: Colors.black, offset: Offset(0, 1)),
            Shadow(blurRadius: 8, color: Colors.black),
          ],
        ),
      ),
    );
  }
}
