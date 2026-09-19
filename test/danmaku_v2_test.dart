import 'package:embyplayer/src/features/danmaku/data/dandanplay_service.dart';
import 'package:embyplayer/src/features/danmaku/presentation/danmaku_overlay.dart';
import 'package:embyplayer/src/features/danmaku/presentation/danmaku_settings_sheet.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DanmakuPreferences', () {
    test('serializes and deserializes correctly', () {
      const prefs = DanmakuPreferences(
        enabled: false,
        offsetMilliseconds: 1500,
        opacity: 0.7,
        fontSize: 18.0,
        displayArea: 0.25,
        blockedKeywords: ['剧透', '广告'],
      );

      final json = prefs.toJson();
      final copy = DanmakuPreferences.fromJson(json);

      expect(copy.enabled, isFalse);
      expect(copy.offsetMilliseconds, 1500);
      expect(copy.opacity, 0.7);
      expect(copy.fontSize, 18.0);
      expect(copy.displayArea, 0.25);
      expect(copy.blockedKeywords, ['剧透', '广告']);
      expect(copy, equals(prefs));
    });
  });

  group('DanmakuOverlay', () {
    final testItems = [
      const DanmakuItem(
        timeSeconds: 10.0,
        type: 1,
        color: 16777215,
        text: '第一条弹幕',
      ),
      const DanmakuItem(
        timeSeconds: 12.0,
        type: 1,
        color: 16777215,
        text: '包含剧透的危险弹幕',
      ),
      const DanmakuItem(
        timeSeconds: 20.0,
        type: 1,
        color: 16777215,
        text: '未来的弹幕',
      ),
    ];

    testWidgets('shows items active within timeline window', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuOverlay(
                items: testItems,
                position: const Duration(seconds: 13),
              ),
            ),
          ),
        ),
      );

      expect(find.text('第一条弹幕'), findsOneWidget);
      expect(find.text('包含剧透的危险弹幕'), findsOneWidget);
      expect(find.text('未来的弹幕'), findsNothing);
    });

    testWidgets('filters out blocked keywords', (tester) async {
      const prefs = DanmakuPreferences(
        blockedKeywords: ['剧透'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuOverlay(
                items: testItems,
                position: const Duration(seconds: 13),
                preferences: prefs,
              ),
            ),
          ),
        ),
      );

      expect(find.text('第一条弹幕'), findsOneWidget);
      expect(find.text('包含剧透的危险弹幕'), findsNothing);
    });

    testWidgets('applies timeline calibration offset', (tester) async {
      // With +2000ms offset, position 8s becomes 10s effective time -> '第一条弹幕' (at 10s) is now active!
      const prefs = DanmakuPreferences(
        offsetMilliseconds: 2000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuOverlay(
                items: testItems,
                position: const Duration(seconds: 8),
                preferences: prefs,
              ),
            ),
          ),
        ),
      );

      expect(find.text('第一条弹幕'), findsOneWidget);
    });

    testWidgets('renders nothing when disabled', (tester) async {
      const prefs = DanmakuPreferences(enabled: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuOverlay(
                items: testItems,
                position: const Duration(seconds: 13),
                preferences: prefs,
              ),
            ),
          ),
        ),
      );

      expect(find.text('第一条弹幕'), findsNothing);
    });
  });

  group('DanmakuSettingsSheet', () {
    testWidgets('updates offset on button tap', (tester) async {
      DanmakuPreferences? updated;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DanmakuSettingsSheet(
              preferences: const DanmakuPreferences(),
              onPreferencesChanged: (p) => updated = p,
            ),
          ),
        ),
      );

      expect(find.text('弹幕设置 (Danmaku 2.0)'), findsOneWidget);
      expect(find.text('+0.5s'), findsOneWidget);

      await tester.tap(find.text('+0.5s'));
      await tester.pumpAndSettle();

      expect(updated, isNotNull);
      expect(updated!.offsetMilliseconds, 500);
    });
  });
}
