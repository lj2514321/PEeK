import 'dart:async';

import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/domain/media_item.dart';
import 'package:embyplayer/src/core/presentation/peek_motion.dart';
import 'package:embyplayer/src/features/details/presentation/media_detail_page.dart';
import 'package:flutter/material.dart';

/// Renders the detail page for an item once, offscreen, as soon as the pointer
/// shows intent — so the first real navigation does not pay the one-time
/// pipeline compilation and image decode.
///
/// Why this is cheap: most of the cost is process-global. The startup
/// exerciser (`PeekPipelineExerciser`) already compiles the shared page and
/// transition pipelines, which measured 502 ms of first-push raster down to
/// ~155 ms; the residual per-item work is what this covers (a real page
/// rendered once brings the next push to ~20 ms).
///
/// Why it is invisible: the render is an overlay entry whose opaque cover is
/// painted immediately on top of the page, and the whole entry is wrapped in
/// [IgnorePointer], so it can neither be seen nor clicked. Painting still
/// happens — that is the entire point — because Flutter paints both layers of
/// the stack.
abstract final class PeekDetailPrewarm {
  /// Items already rendered, most recent last. Bounded: this is a warm-up
  /// cache, not a feature cache.
  static final List<String> _warmed = <String>[];

  /// Only one offscreen render at a time: each costs a frame of GPU work.
  static String? _inFlight;
  static Timer? _dwell;

  static const int _maxRemembered = 96;

  /// How long the pointer must rest on a card before a render is worth it, so
  /// sweeping the pointer across a grid does not trigger anything.
  static const Duration _dwellDuration = Duration(milliseconds: 80);

  static bool get isWarming => _inFlight != null;

  /// Call from a `MouseRegion.onEnter` on anything that opens a detail page.
  static void schedule(BuildContext context, {required MediaItem item}) {
    // Never in widget tests: this inserts overlay entries and burns frames.
    if (AppMotion.isTest) return;
    if (item.kind == MediaItemKind.person) return;
    if (_warmed.contains(item.id) || _inFlight == item.id) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _inFlight = item.id;
    _dwell?.cancel();
    _dwell = Timer(_dwellDuration, () {
      if (_inFlight != item.id) return;
      _render(overlay, item);
    });
  }

  static void _render(OverlayState overlay, MediaItem item) {
    var removed = false;
    var settleHandled = false;
    late final OverlayEntry entry;

    void remove() {
      if (removed) return;
      removed = true;
      if (entry.mounted) {
        try {
          entry.remove();
        } catch (_) {
          // The overlay may already be gone during teardown.
        }
      }
      _remember(item.id);
      if (_inFlight == item.id) _inFlight = null;
    }

    // The transition drops its anti-aliased rounded clip when it completes
    // (`ClipRRect` -> `Clip.none`), which re-rasterizes the whole page without
    // the clip mask. Measured: that single frame was 142 ms of the first
    // entry, so the warm-up must paint the settled state too, not just the
    // animated one.
    void onSettled() {
      if (settleHandled) return;
      settleHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => remove());
      });
    }

    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Runs the real transition wrapper: the scaled, anti-aliased
              // rounded-clip composite compiles a different pipeline than a
              // settled page, and it is worth ~174 ms of the first-entry spike.
              _PrewarmStage(item: item, onSettled: onSettled),
              // Painted after the page, so the whole thing stays invisible
              // while still being rasterized.
              const ColoredBox(color: AppColors.canvas),
            ],
          ),
        ),
      ),
    );

    overlay.insert(entry);

    // Safety net: if the transition never settles (window hidden, app closing),
    // release the slot so a later hover can try again.
    Timer(const Duration(seconds: 3), remove);
  }

  static void _remember(String id) {
    _warmed.remove(id);
    _warmed.add(id);
    while (_warmed.length > _maxRemembered) {
      _warmed.removeAt(0);
    }
  }
}

/// The offscreen payload: the real page, inside the real transition, driven
/// through the same scales the user will see.
class _PrewarmStage extends StatefulWidget {
  const _PrewarmStage({required this.item, this.onSettled});

  final MediaItem item;

  /// Fired once the transition reaches its completed state, i.e. after the
  /// clip has been dropped and the page has been re-rasterized unclipped.
  final VoidCallback? onSettled;

  @override
  State<_PrewarmStage> createState() => _PrewarmStageState();
}

class _PrewarmStageState extends State<_PrewarmStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onSettled?.call();
        });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PeekSpatialTransition(
      animation: _controller,
      secondaryAnimation: kAlwaysDismissedAnimation,
      originAlignment: Alignment.center,
      child: MediaDetailPage(
        account: null,
        initialItem: widget.item,
        isWarmup: true,
      ),
    );
  }
}

/// Wraps any card that opens a detail page and schedules a background render
/// the first time the pointer rests on it.
class PeekDetailPrewarmOnHover extends StatelessWidget {
  const PeekDetailPrewarmOnHover({
    super.key,
    required this.item,
    required this.child,
  });

  final MediaItem item;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => PeekDetailPrewarm.schedule(context, item: item),
      child: child,
    );
  }
}
