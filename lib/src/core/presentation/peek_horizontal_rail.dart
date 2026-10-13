import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/core/presentation/peek_smooth_scroll.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class PeekHorizontalRail extends StatefulWidget {
  const PeekHorizontalRail({
    super.key,
    required this.railId,
    required this.semanticLabel,
    required this.height,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
    this.spacing = 14.0,
  });

  final String railId;
  final String semanticLabel;
  final double height;
  final int itemCount;
  final double itemExtent;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;

  @override
  State<PeekHorizontalRail> createState() => _PeekHorizontalRailState();
}

class _PeekHorizontalRailState extends State<PeekHorizontalRail> {
  final _controller = SmoothScrollController();
  bool _canMoveBackward = false;
  bool _canMoveForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateControls);
    _scheduleControlsUpdate();
  }

  @override
  void didUpdateWidget(covariant PeekHorizontalRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount ||
        oldWidget.itemExtent != widget.itemExtent) {
      _scheduleControlsUpdate();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updateControls)
      ..dispose();
    super.dispose();
  }

  void _scheduleControlsUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateControls());
  }

  void _updateControls() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final backward = position.pixels > position.minScrollExtent + 1;
    final forward = position.pixels < position.maxScrollExtent - 1;
    if (backward == _canMoveBackward && forward == _canMoveForward) return;
    setState(() {
      _canMoveBackward = backward;
      _canMoveForward = forward;
    });
  }

  Future<void> _move(int direction) async {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final distance = position.viewportDimension * 0.78 * direction;
    final target = (position.pixels + distance)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    final duration = AppMotion.responsive(context, AppMotion.standard);
    if (duration == Duration.zero) {
      _controller.jumpTo(target);
      return;
    }
    await _controller.animateTo(
      target,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showControls =
            constraints.maxWidth >= 640 && widget.itemCount > 1;
        return Semantics(
          container: true,
          label: widget.semanticLabel,
          child: SizedBox(
            height: widget.height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showControls) ...[
                  _RailDirectionButton(
                    key: ValueKey('${widget.railId}-previous'),
                    tooltip: '向前浏览',
                    icon: Icons.chevron_left_rounded,
                    enabled: _canMoveBackward,
                    onPressed: () => _move(-1),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ScrollConfiguration(
                    behavior: const _RailScrollBehavior(),
                    child: ListView.separated(
                      key: ValueKey(widget.railId),
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.itemCount,
                      separatorBuilder: (_, _) =>
                          SizedBox(width: widget.spacing),
                      itemBuilder: (context, index) => SizedBox(
                        width: widget.itemExtent,
                        child: PeekStaggeredGridItem(
                          key: ValueKey('${widget.railId}-stagger-$index'),
                          index: index,
                          columns: 8,
                          horizontal: true,
                          child: widget.itemBuilder(context, index),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showControls) ...[
                  const SizedBox(width: 8),
                  _RailDirectionButton(
                    key: ValueKey('${widget.railId}-next'),
                    tooltip: '向后浏览',
                    icon: Icons.chevron_right_rounded,
                    enabled: _canMoveForward,
                    onPressed: () => _move(1),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RailDirectionButton extends StatelessWidget {
  const _RailDirectionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AppMotion.responsive(context, AppMotion.fast),
      opacity: enabled ? 1 : 0.3,
      child: IconButton(
        tooltip: tooltip,
        onPressed: enabled ? onPressed : null,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(42),
          backgroundColor: enabled
              ? AppColors.spotlight.withValues(alpha: 0.12)
              : AppColors.surfaceLow,
          foregroundColor: enabled
              ? AppColors.spotlight
              : AppColors.textTertiary,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _RailScrollBehavior extends MaterialScrollBehavior {
  const _RailScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
