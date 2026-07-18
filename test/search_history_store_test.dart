import 'dart:io';

import 'package:embyplayer/src/core/storage/search_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keeps eight recent queries and removes case-insensitive duplicates',
    () async {
      final store = MemorySearchHistoryStore(['Dune', 'Alien']);

      await store.add('dune');
      expect(await store.read(), ['dune', 'Alien']);
      for (var index = 0; index < 9; index++) {
        await store.add('query-$index');
      }

      final history = await store.read();
      expect(history, hasLength(8));
      expect(history.first, 'query-8');
    },
  );

  test('persists and clears search history on disk', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peek-search-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    await JsonSearchHistoryStore(directory: directory).add('银翼杀手');
    final restored = JsonSearchHistoryStore(directory: directory);

    expect(await restored.read(), ['银翼杀手']);
    await restored.clear();
    expect(await JsonSearchHistoryStore(directory: directory).read(), isEmpty);
  });
}
