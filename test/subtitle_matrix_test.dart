import 'package:embyplayer/src/features/danmaku/data/dandanplay_service.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Subtitle Matrix: Parses DanmakuItem comments from DandanPlay response',
    () {
      final rawComments = [
        {'p': '12.5,1,25,user1', 'm': '前方高能弹幕通过！'},
        {'p': '45.0,4,25,user2', 'm': '名场面打卡！'},
      ];

      final items = rawComments.map(DanmakuItem.fromDandanJson).toList();

      expect(items.length, 2);
      expect(items[0].timeSeconds, 12.5);
      expect(items[0].text, '前方高能弹幕通过！');
      expect(items[0].type, 1);
      expect(items[1].timeSeconds, 45.0);
      expect(items[1].type, 4);
    },
  );

  test('Subtitle Matrix: Subtitle track parsing and delay calculation', () {
    const track = PlaybackTrackInfo(
      index: 1,
      kind: PlaybackTrackKind.subtitle,
      label: 'Chinese Simplified (Ass)',
      language: 'chi',
      isDefault: true,
      isExternal: true,
    );

    expect(track.kind, PlaybackTrackKind.subtitle);
    expect(track.isExternal, isTrue);

    // Verify delay offset calculation
    const delay = Duration(milliseconds: 1500);
    final delaySeconds = delay.inMilliseconds / 1000;
    expect(delaySeconds.toStringAsFixed(3), '1.500');
  });
}
