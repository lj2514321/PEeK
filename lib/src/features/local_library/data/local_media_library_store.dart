import 'dart:convert';
import 'dart:io';

import 'package:embyplayer/src/features/local_library/domain/local_media_library.dart';

abstract interface class LocalMediaLibraryStore {
  Future<List<LocalMediaLibrary>> read();

  Future<void> write(List<LocalMediaLibrary> libraries);
}

class MemoryLocalMediaLibraryStore implements LocalMediaLibraryStore {
  MemoryLocalMediaLibraryStore([Iterable<LocalMediaLibrary> initial = const []])
    : _libraries = initial.toList();

  List<LocalMediaLibrary> _libraries;

  @override
  Future<List<LocalMediaLibrary>> read() async => List.unmodifiable(_libraries);

  @override
  Future<void> write(List<LocalMediaLibrary> libraries) async {
    _libraries = List.of(libraries);
  }
}

class JsonLocalMediaLibraryStore implements LocalMediaLibraryStore {
  JsonLocalMediaLibraryStore({Directory? directory})
    : _directory = directory ?? _defaultDirectory();

  final Directory _directory;
  List<LocalMediaLibrary>? _libraries;
  Future<void> _writeQueue = Future.value();

  File get _file => File(
    '${_directory.path}${Platform.pathSeparator}local_libraries_v1.json',
  );

  static Directory _defaultDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? Directory.systemTemp.path
        : localAppData;
    return Directory('$root${Platform.pathSeparator}PEeK');
  }

  @override
  Future<List<LocalMediaLibrary>> read() async {
    final loaded = _libraries;
    if (loaded != null) return List.unmodifiable(loaded);
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        final rawLibraries = decoded is Map ? decoded['libraries'] : null;
        if (rawLibraries is List) {
          _libraries = rawLibraries
              .map(LocalMediaLibrary.fromJson)
              .whereType<LocalMediaLibrary>()
              .toList(growable: false);
          return List.unmodifiable(_libraries!);
        }
      }
    } on FileSystemException {
      // A damaged optional catalog must not prevent PEeK from starting.
    } on FormatException {
      // Ignore a partial or outdated file and replace it on the next write.
    }
    _libraries = [];
    return const [];
  }

  @override
  Future<void> write(List<LocalMediaLibrary> libraries) {
    _libraries = List.of(libraries);
    final snapshot = jsonEncode({
      'version': 1,
      'libraries': libraries.map((library) => library.toJson()).toList(),
    });
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      await _directory.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      if (await _file.exists()) await _file.delete();
      await temporary.rename(_file.path);
    });
    return _writeQueue;
  }
}
