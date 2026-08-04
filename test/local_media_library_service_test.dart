import 'dart:io';

import 'package:embyplayer/src/features/local_library/data/local_media_library_service.dart';
import 'package:embyplayer/src/features/local_library/data/local_media_library_store.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late Directory mediaDirectory;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('peek-local-library-');
    mediaDirectory = await Directory(
      '${temporary.path}${Platform.pathSeparator}Cinema',
    ).create();
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('persists, restores and removes local media libraries', () async {
    final catalogDirectory = Directory(
      '${temporary.path}${Platform.pathSeparator}catalog',
    );
    final store = JsonLocalMediaLibraryStore(directory: catalogDirectory);
    final service = LocalMediaLibraryService(
      store,
      clock: () => DateTime.utc(2026, 8, 4),
    );

    final first = await service.addDirectory(mediaDirectory.path);
    final duplicate = await service.addDirectory(mediaDirectory.path);

    expect(duplicate.id, first.id);
    expect(await service.getLibraries(), hasLength(1));

    final restored = await JsonLocalMediaLibraryStore(
      directory: catalogDirectory,
    ).read();
    expect(restored.single.path, mediaDirectory.absolute.path);
    expect(restored.single.name, 'Cinema');

    await service.removeLibrary(first.id);
    expect(await service.getLibraries(), isEmpty);
    expect(await mediaDirectory.exists(), isTrue);
  });

  test('browses supported media, folders and local artwork', () async {
    final movie = File(
      '${mediaDirectory.path}${Platform.pathSeparator}Movie.2024.mkv',
    );
    await movie.writeAsBytes([0, 1, 2, 3]);
    await File(
      '${mediaDirectory.path}${Platform.pathSeparator}Movie.2024.jpg',
    ).writeAsBytes([0]);
    await File(
      '${mediaDirectory.path}${Platform.pathSeparator}notes.txt',
    ).writeAsString('ignore me');
    await Directory(
      '${mediaDirectory.path}${Platform.pathSeparator}Season 01',
    ).create();

    final service = LocalMediaLibraryService(MemoryLocalMediaLibraryStore());
    final library = await service.addDirectory(mediaDirectory.path);
    final root = service.libraryItem(library);
    final page = await service.getItems(root);

    expect(page.totalRecordCount, 2);
    expect(page.items.first.kind, MediaItemKind.folder);
    final item = page.items.singleWhere(
      (item) => item.kind == MediaItemKind.video,
    );
    expect(item.name, 'Movie 2024');
    expect(item.productionYear, 2024);
    expect(item.source, MediaItemSource.local);
    expect(item.fileSize, 4);
    expect(item.imageUri?.scheme, 'file');

    final plan = await service.createPlaybackPlan(item);
    expect(plan.streamUri.scheme, 'file');
    expect(
      plan.streamUri.toFilePath(windows: Platform.isWindows),
      movie.absolute.path,
    );
  });

  test('reads the first usable STRM source and paginates locally', () async {
    final strm = File(
      '${mediaDirectory.path}${Platform.pathSeparator}Remote.strm',
    );
    await strm.writeAsString(
      '# comment\n\nhttps://media.example.test/movie/master.m3u8\n',
    );
    await File(
      '${mediaDirectory.path}${Platform.pathSeparator}Second.mp4',
    ).writeAsBytes([0]);

    final service = LocalMediaLibraryService(MemoryLocalMediaLibraryStore());
    final root = service.libraryItem(
      await service.addDirectory(mediaDirectory.path),
    );
    final firstPage = await service.getItems(root, limit: 1);
    final secondPage = await service.getItems(root, startIndex: 1, limit: 1);

    expect(firstPage.items, hasLength(1));
    expect(firstPage.nextStartIndex, 1);
    expect(secondPage.items, hasLength(1));
    expect(secondPage.nextStartIndex, 2);

    final all = await service.getItems(root);
    final item = all.items.singleWhere((item) => item.sourcePath == strm.path);
    final plan = await service.createPlaybackPlan(item);
    expect(
      plan.streamUri,
      Uri.parse('https://media.example.test/movie/master.m3u8'),
    );
  });

  test('rejects files outside configured local libraries', () async {
    final service = LocalMediaLibraryService(MemoryLocalMediaLibraryStore());
    await service.addDirectory(mediaDirectory.path);
    final outside = File(
      '${temporary.path}${Platform.pathSeparator}outside.mp4',
    );
    await outside.writeAsBytes([0]);
    final item = MediaItem(
      id: 'outside',
      name: 'Outside',
      kind: MediaItemKind.video,
      source: MediaItemSource.local,
      sourcePath: outside.path,
    );

    expect(
      () => service.createPlaybackPlan(item),
      throwsA(isA<LocalMediaLibraryException>()),
    );
  });

  test('applies local type and status filters safely', () async {
    await File(
      '${mediaDirectory.path}${Platform.pathSeparator}Track.flac',
    ).writeAsBytes([0]);
    await File(
      '${mediaDirectory.path}${Platform.pathSeparator}Film.mp4',
    ).writeAsBytes([0]);
    final service = LocalMediaLibraryService(MemoryLocalMediaLibraryStore());
    final root = service.libraryItem(
      await service.addDirectory(mediaDirectory.path),
    );

    final movies = await service.getItems(
      root,
      kind: MediaLibraryKindFilter.movies,
    );
    final favorites = await service.getItems(
      root,
      status: MediaLibraryStatusFilter.favorites,
    );

    expect(movies.items.map((item) => item.name), ['Film']);
    expect(favorites.items, isEmpty);
  });
}
