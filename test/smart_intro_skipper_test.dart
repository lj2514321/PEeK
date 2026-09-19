import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/player/domain/smart_intro_skipper.dart';
import 'package:embyplayer/src/features/player/presentation/skip_intro_overlay.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartIntroSkipper', () {
    test('detects intro chapter by keyword OP / Opening / 片头', () {
      final chapters = [
        const MediaChapter(
          name: 'Prologue',
          startPosition: Duration(seconds: 0),
        ),
        const MediaChapter(
          name: 'OP: The Hero',
          startPosition: Duration(seconds: 90),
        ),
        const MediaChapter(
          name: 'Main Story',
          startPosition: Duration(seconds: 180),
        ),
      ];

      final intro = SmartIntroSkipper.detectIntro(chapters);
      expect(intro, isNotNull);
      expect(intro!.startPosition, const Duration(seconds: 90));
      expect(intro.endPosition, const Duration(seconds: 180));
      expect(intro.kind, IntroOutroKind.intro);
      expect(intro.contains(const Duration(seconds: 100)), isTrue);
      expect(intro.contains(const Duration(seconds: 180)), isFalse);
    });

    test('detects outro chapter by keyword ED / Ending / 片尾', () {
      final chapters = [
        const MediaChapter(
          name: 'Part A',
          startPosition: Duration(seconds: 0),
        ),
        const MediaChapter(
          name: '片尾曲 (Ending)',
          startPosition: Duration(minutes: 22),
        ),
      ];

      final outro = SmartIntroSkipper.detectOutro(
        chapters,
        const Duration(minutes: 24),
      );
      expect(outro, isNotNull);
      expect(outro!.startPosition, const Duration(minutes: 22));
      expect(outro.endPosition, const Duration(minutes: 24));
      expect(outro.kind, IntroOutroKind.outro);
      expect(outro.contains(const Duration(minutes: 23)), isTrue);
    });

    test('falls back to estimated intro/outro when allowFallback is true', () {
      final fallbackIntro = SmartIntroSkipper.detectIntro(
        const [],
        duration: const Duration(minutes: 24),
        fallbackSeconds: 85,
        allowFallback: true,
      );
      expect(fallbackIntro, isNotNull);
      expect(fallbackIntro!.startPosition, Duration.zero);
      expect(fallbackIntro.endPosition, const Duration(seconds: 85));

      final fallbackOutro = SmartIntroSkipper.detectOutro(
        const [],
        const Duration(minutes: 24),
        fallbackSeconds: 90,
        allowFallback: true,
      );
      expect(fallbackOutro, isNotNull);
      expect(
        fallbackOutro!.startPosition,
        const Duration(minutes: 24) - const Duration(seconds: 90),
      );
      expect(fallbackOutro.endPosition, const Duration(minutes: 24));
    });

    test('does not fallback for short duration under 3 minutes', () {
      final intro = SmartIntroSkipper.detectIntro(
        const [],
        duration: const Duration(minutes: 2),
        allowFallback: true,
      );
      expect(intro, isNull);

      final outro = SmartIntroSkipper.detectOutro(
        const [],
        const Duration(minutes: 2),
        allowFallback: true,
      );
      expect(outro, isNull);
    });
  });

  group('SkipIntroPreferences', () {
    test('serializes and deserializes correctly', () {
      const prefs = SkipIntroPreferences(
        enabled: true,
        autoSkip: false,
        countdownSeconds: 5,
        fallbackIntroSeconds: 100,
        fallbackOutroSeconds: 110,
      );

      final json = prefs.toJson();
      final copy = SkipIntroPreferences.fromJson(json);

      expect(copy.enabled, isTrue);
      expect(copy.autoSkip, isFalse);
      expect(copy.countdownSeconds, 5);
      expect(copy.fallbackIntroSeconds, 100);
      expect(copy.fallbackOutroSeconds, 110);
      expect(copy, equals(prefs));
    });
  });

  group('SkipIntroOverlay widget', () {
    testWidgets('renders countdown and responds to tap', (tester) async {
      var skipped = false;
      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SkipIntroOverlay(
              label: '跳过片头',
              countdownSeconds: 3,
              onSkip: () => skipped = true,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      expect(find.text('跳过片头 (3s)'), findsOneWidget);
      expect(find.byIcon(Icons.fast_forward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.text('跳过片头 (3s)'));
      expect(skipped, isTrue);

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(closed, isTrue);
    });
  });
}
