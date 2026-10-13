import 'package:embyplayer/src/features/analytics/data/viewing_history_store.dart';
import 'package:embyplayer/src/features/danmaku/data/dandanplay_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DanmakuItem parses DandanPlay JSON comment correctly', () {
    final json = {'p': '12.5,1,16777215,user1', 'm': '这是一条弹幕测试'};
    final item = DanmakuItem.fromDandanJson(json);
    expect(item.timeSeconds, 12.5);
    expect(item.type, 1);
    expect(item.color, 16777215);
    expect(item.text, '这是一条弹幕测试');
  });

  test('ViewingHistoryStore records viewing history correctly', () async {
    final store = ViewingHistoryStore();
    final initialRecords = await store.readRecords();
    expect(initialRecords, isNotEmpty);

    await store.recordViewing(minutes: 45, kind: 'movie');
    final updatedRecords = await store.readRecords();
    expect(updatedRecords.length, initialRecords.length + 1);
    expect(updatedRecords.last.minutes, 45);
    expect(updatedRecords.last.kind, 'movie');
  });
}
