import 'package:embyplayer/src/features/servers/domain/media_item.dart';

enum IntroOutroKind { intro, outro }

class IntroOutroRange {
  const IntroOutroRange({
    required this.startPosition,
    required this.endPosition,
    required this.kind,
    this.label,
  });

  final Duration startPosition;
  final Duration endPosition;
  final IntroOutroKind kind;
  final String? label;

  bool contains(Duration position) {
    return position >= startPosition && position < endPosition;
  }
}

abstract final class SmartIntroSkipper {
  static final RegExp _introRegex = RegExp(
    r'(intro|opening|\bop\b|片头)',
    caseSensitive: false,
  );

  static final RegExp _outroRegex = RegExp(
    r'(outro|ending|\bed\b|credits|片尾)',
    caseSensitive: false,
  );

  static IntroOutroRange? detectIntro(
    List<MediaChapter> chapters, {
    Duration? duration,
    int fallbackSeconds = 90,
    bool allowFallback = false,
  }) {
    if (chapters.isNotEmpty) {
      for (var i = 0; i < chapters.length; i++) {
        final chapter = chapters[i];
        if (_introRegex.hasMatch(chapter.name)) {
          final nextChapter = (i + 1 < chapters.length)
              ? chapters[i + 1]
              : null;
          final end = nextChapter != null
              ? nextChapter.startPosition
              : (chapter.startPosition + Duration(seconds: fallbackSeconds));
          if (end > chapter.startPosition) {
            return IntroOutroRange(
              startPosition: chapter.startPosition,
              endPosition: end,
              kind: IntroOutroKind.intro,
              label: chapter.name,
            );
          }
        }
      }
    }

    if (allowFallback &&
        duration != null &&
        duration > const Duration(minutes: 3) &&
        fallbackSeconds > 0) {
      return IntroOutroRange(
        startPosition: Duration.zero,
        endPosition: Duration(seconds: fallbackSeconds),
        kind: IntroOutroKind.intro,
        label: '预估片头',
      );
    }

    return null;
  }

  static IntroOutroRange? detectOutro(
    List<MediaChapter> chapters,
    Duration duration, {
    int fallbackSeconds = 90,
    bool allowFallback = false,
  }) {
    if (duration <= const Duration(minutes: 3)) return null;

    if (chapters.isNotEmpty) {
      for (var i = chapters.length - 1; i >= 0; i--) {
        final chapter = chapters[i];
        if (_outroRegex.hasMatch(chapter.name)) {
          if (chapter.startPosition < duration) {
            return IntroOutroRange(
              startPosition: chapter.startPosition,
              endPosition: duration,
              kind: IntroOutroKind.outro,
              label: chapter.name,
            );
          }
        }
      }
    }

    if (allowFallback && fallbackSeconds > 0) {
      final start = duration - Duration(seconds: fallbackSeconds);
      if (start > Duration.zero) {
        return IntroOutroRange(
          startPosition: start,
          endPosition: duration,
          kind: IntroOutroKind.outro,
          label: '预估片尾',
        );
      }
    }

    return null;
  }
}
