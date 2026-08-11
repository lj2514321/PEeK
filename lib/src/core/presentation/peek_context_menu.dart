import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/material.dart';

/// Context menu item entry model.
class PeekContextMenuItem {
  const PeekContextMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    this.danger = false,
    this.onTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool danger;
  final VoidCallback? onTap;
}

/// Wraps any widget with desktop right-click (secondary tap) context menu support.
class PeekContextMenuRegion extends StatelessWidget {
  const PeekContextMenuRegion({
    super.key,
    required this.child,
    required this.items,
  });

  final Widget child;
  final List<PeekContextMenuItem> Function(BuildContext context) items;

  void _showContextMenu(BuildContext context, Offset globalPosition) {
    final menuItems = items(context);
    if (menuItems.isEmpty) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      elevation: 12,
      color: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18), width: 1.0),
      ),
      items: [
        for (final item in menuItems)
          PopupMenuItem<String>(
            value: item.id,
            onTap: item.onTap,
            height: 38,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: item.danger
                      ? AppColors.error
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: item.danger
                        ? AppColors.error
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: child,
    );
  }
}
