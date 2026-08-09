import 'package:embyplayer/src/features/danmaku/data/dandanplay_service.dart';
import 'package:flutter/material.dart';

class DanmakuOverlay extends StatelessWidget {
  const DanmakuOverlay({
    super.key,
    required this.items,
    required this.position,
    this.enabled = true,
    this.opacity = 0.85,
    this.fontSize = 16.0,
  });

  final List<DanmakuItem> items;
  final Duration position;
  final bool enabled;
  final double opacity;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (!enabled || items.isEmpty) return const SizedBox.shrink();

    final currentSec = position.inMilliseconds / 1000.0;
    // Show items active within [currentSec - 6.0, currentSec]
    final activeItems = items.where((item) {
      final delta = currentSec - item.timeSeconds;
      return delta >= 0.0 && delta <= 6.0;
    }).toList(growable: false);

    if (activeItems.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.1, 1.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            const trackCount = 6;
            final trackHeight = height / (trackCount + 2);

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
  }) {
    final progress = (currentSec - item.timeSeconds) / 6.0;
    final trackIndex = index % 6;
    final top = (trackIndex + 1) * trackHeight;
    final left = width - (progress * (width + 300));

    final colorValue = item.color == 16777215 ? 0xFFFFFFFF : item.color | 0xFF000000;

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
