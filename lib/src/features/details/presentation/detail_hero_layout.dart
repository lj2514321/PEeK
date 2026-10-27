import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/domain/media_item.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:flutter/material.dart';

/// Where the detail hero puts its poster, as a pure function of the window.
///
/// A shared-element flight has to know its destination *before* the page is
/// laid out — otherwise the artwork cannot leave the card on the first frame,
/// and a flight that starts one frame late reads as a stutter. The page and the
/// route therefore both read these numbers instead of each keeping a copy: a
/// few pixels of drift would make the poster jump at hand-off.
///
/// `test/detail_hero_layout_test.dart` holds the two together by measuring the
/// real poster at several window sizes.
@immutable
class DetailHeroLayout {
  const DetailHeroLayout._({
    required this.screenWidth,
    required this.contentWidth,
    required this.stacked,
    required this.compact,
    required this.posterWidth,
    required this.padding,
  });

  factory DetailHeroLayout.of(Size screen) {
    final contentWidth = screen.width > _maxContentWidth
        ? _maxContentWidth
        : screen.width;
    // Two independent breakpoints: `stacked` folds the two-column hero into
    // one, `compact` only shrinks the controls. Below 900px the poster, the gap
    // and a readable copy column stop fitting side by side.
    final stacked = contentWidth < _stackBreakpoint;
    final compact = contentWidth < _compactBreakpoint;
    final posterWidth = stacked
        ? 160.0
        : (contentWidth * 0.32).clamp(240.0, 360.0).toDouble();
    return DetailHeroLayout._(
      screenWidth: screen.width,
      contentWidth: contentWidth,
      stacked: stacked,
      compact: compact,
      posterWidth: posterWidth,
      padding: stacked
          ? const EdgeInsets.fromLTRB(20, 56, 20, 24)
          : const EdgeInsets.fromLTRB(48, 76, 48, 44),
    );
  }

  static const double _maxContentWidth = 1240;
  static const double _stackBreakpoint = 900;
  static const double _compactBreakpoint = 768;

  /// Poster aspect ratio, shared with [DetailPosterArt].
  static const double posterAspectRatio = 2 / 3;

  final double screenWidth;
  final double contentWidth;
  final bool stacked;
  final bool compact;
  final double posterWidth;
  final EdgeInsets padding;

  /// The poster's rectangle in screen coordinates.
  ///
  /// Exact only while the hero is the first, unscrolled child of a full-screen
  /// page, which is the only moment the flight needs it.
  Rect get posterRect => Rect.fromLTWH(
    (screenWidth - contentWidth) / 2 + padding.left,
    padding.top,
    posterWidth,
    posterWidth / posterAspectRatio,
  );
}

/// The poster artwork on its own.
///
/// The page and the flight must paint the *same* widget: the hand-off at the
/// end of the flight is only invisible if the pixels are already identical.
/// Callers own the box (the hero adds the 2:3 aspect, the flight adds the
/// transform), and it is built through [PeekMediaImage] with the same cache key
/// the grid used, so the first frame is a synchronous cache hit instead of a
/// placeholder flash.
class DetailPosterArt extends StatelessWidget {
  const DetailPosterArt({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return PosterAmbientGlow(
      glowColor: const Color(0x454A90E2),
      borderRadius: AppRadius.value,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: AppRadius.borderRadius,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 32,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: PeekMediaImage(
          uri: item.imageUri ?? item.backdropUri,
          headers: item.imageHeaders,
          kind: PeekMediaImageKind.poster,
          placeholderIconSize: 58,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
        ),
      ),
    );
  }
}
