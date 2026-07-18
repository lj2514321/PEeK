import 'package:embyplayer/src/features/player/domain/playback_queue.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sorts regular episodes across seasons and excludes specials', () {
    final current = _episode('s1e2', season: 1, episode: 2);
    final queue = PlaybackQueue.fromEpisodes(
      current: current,
      episodes: [
        _episode('special', season: 0, episode: 1),
        _episode('s2e1', season: 2, episode: 1),
        current,
        _episode('s1e1', season: 1, episode: 1),
      ],
    );

    expect(queue.items.map((item) => item.id), ['s1e1', 's1e2', 's2e1']);
    expect(queue.current.id, 's1e2');
    expect(queue.previous?.id, 's1e1');
    expect(queue.next?.id, 's2e1');
  });

  test('keeps special episodes in their own playback queue', () {
    final current = _episode('special-2', season: 0, episode: 2);
    final queue = PlaybackQueue.fromEpisodes(
      current: current,
      episodes: [
        _episode('s1e1', season: 1, episode: 1),
        current,
        _episode('special-1', season: 0, episode: 1),
      ],
    );

    expect(queue.items.map((item) => item.id), ['special-1', 'special-2']);
    expect(queue.hasPrevious, isTrue);
    expect(queue.hasNext, isFalse);
  });

  test('selects a queue item without changing the ordered episode list', () {
    final queue = PlaybackQueue.fromEpisodes(
      current: _episode('s1e1', season: 1, episode: 1),
      episodes: [
        _episode('s1e1', season: 1, episode: 1),
        _episode('s1e2', season: 1, episode: 2),
      ],
    );

    final selected = queue.select(1);

    expect(selected.current.id, 's1e2');
    expect(selected.items, same(queue.items));
    expect(selected.select(8), same(selected));
  });
}

MediaItem _episode(String id, {required int season, required int episode}) {
  return MediaItem(
    id: id,
    name: id,
    kind: MediaItemKind.episode,
    seriesId: 'series-id',
    parentIndexNumber: season,
    indexNumber: episode,
  );
}
