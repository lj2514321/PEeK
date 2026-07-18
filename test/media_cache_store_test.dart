import 'dart:io';

import 'package:embyplayer/src/core/storage/media_cache_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists media metadata across cache store instances', () async {
    final directory = await Directory.systemTemp.createTemp(
      'projection_booth_cache_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    final first = JsonFileMediaCacheStore(directory: directory);
    await first.write('library-key', {
      'Items': [
        {'Id': 'movie-id', 'Name': '示例电影'},
      ],
    });

    final second = JsonFileMediaCacheStore(directory: directory);
    final cached = await second.read(
      'library-key',
      maxAge: const Duration(hours: 1),
    );

    expect(cached, isNotNull);
    expect((cached!.payload['Items'] as List).single['Name'], '示例电影');
  });

  test('honors cache freshness without deleting stale fallback data', () async {
    var now = DateTime.utc(2026, 7, 18, 12);
    final cache = MemoryMediaCacheStore(clock: () => now);
    await cache.write('key', {'value': 1});

    now = now.add(const Duration(minutes: 11));

    expect(
      await cache.read('key', maxAge: const Duration(minutes: 10)),
      isNull,
    );
    expect((await cache.read('key'))?.payload['value'], 1);
  });
}
