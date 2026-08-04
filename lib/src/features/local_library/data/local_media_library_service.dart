import 'dart:convert';
import 'dart:io';

import 'package:embyplayer/src/features/local_library/data/local_media_library_store.dart';
import 'package:embyplayer/src/features/local_library/domain/local_media_library.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';

class LocalMediaLibraryService {
  LocalMediaLibraryService(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LocalMediaLibraryStore _store;
  final DateTime Function() _clock;

  static const supportedVideoExtensions = {
    '.mkv',
    '.mp4',
    '.avi',
    '.mov',
    '.wmv',
    '.m4v',
    '.ts',
    '.m2ts',
    '.webm',
    '.mpg',
    '.mpeg',
    '.flv',
    '.3gp',
    '.ogv',
    '.rmvb',
    '.vob',
    '.iso',
    '.strm',
  };

  static const supportedAudioExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.wav',
    '.wma',
    '.alac',
    '.ape',
  };

  Future<List<LocalMediaLibrary>> getLibraries() => _store.read();

  Future<LocalMediaLibrary> addDirectory(String path) async {
    final directory = Directory(path).absolute;
    if (!await directory.exists()) {
      throw const LocalMediaLibraryException('选择的文件夹不存在或当前无法访问。');
    }
    final normalized = _normalizePath(directory.path);
    final current = await _store.read();
    for (final library in current) {
      if (_normalizePath(library.path) == normalized) return library;
    }
    final library = LocalMediaLibrary(
      id: _idForPath(directory.path),
      name: _baseName(directory.path),
      path: directory.path,
      addedAt: _clock(),
    );
    await _store.write([...current, library]);
    return library;
  }

  Future<void> removeLibrary(String libraryId) async {
    final current = await _store.read();
    await _store.write(
      current.where((library) => library.id != libraryId).toList(),
    );
  }

  MediaItem libraryItem(LocalMediaLibrary library) {
    return MediaItem(
      id: 'local-library:${library.id}',
      name: library.name,
      kind: MediaItemKind.folder,
      collectionType: 'local',
      source: MediaItemSource.local,
      sourcePath: library.path,
      imageUri: _findArtworkSync(library.path, directory: true),
      dateModified: library.addedAt,
    );
  }

  Future<MediaPage> getItems(
    MediaItem parent, {
    int startIndex = 0,
    int limit = 60,
    MediaLibrarySort sort = MediaLibrarySort.nameAscending,
    MediaLibraryKindFilter kind = MediaLibraryKindFilter.all,
    MediaLibraryStatusFilter status = MediaLibraryStatusFilter.all,
    int? productionYear,
  }) async {
    final path = parent.sourcePath;
    if (!parent.isLocal || path == null || path.isEmpty) {
      throw const LocalMediaLibraryException('本地媒体库路径无效。');
    }
    await _ensureAllowed(path);
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw const LocalMediaLibraryException('本地文件夹已被移动、删除或当前不可访问。');
    }

    final items = <MediaItem>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        final item = await _itemForEntity(entity);
        if (item != null) items.add(item);
      }
    } on FileSystemException catch (error) {
      throw LocalMediaLibraryException(
        error.osError?.message.isNotEmpty == true
            ? '无法读取本地文件夹：${error.osError!.message}'
            : '无法读取本地文件夹，请检查访问权限。',
      );
    }

    final filtered = items.where((item) {
      if (productionYear != null && item.productionYear != productionYear) {
        return false;
      }
      if (!_matchesKind(item, kind)) return false;
      return switch (status) {
        MediaLibraryStatusFilter.all ||
        MediaLibraryStatusFilter.unplayed => true,
        _ => false,
      };
    }).toList();
    _sortItems(filtered, sort);

    final safeStart = startIndex.clamp(0, filtered.length);
    final end = (safeStart + limit).clamp(safeStart, filtered.length);
    return MediaPage(
      items: filtered.sublist(safeStart, end),
      totalRecordCount: filtered.length,
      nextStartIndex: end,
    );
  }

  Future<PlaybackPlan> createPlaybackPlan(MediaItem item) async {
    final path = item.sourcePath;
    if (!item.isLocal || path == null || path.isEmpty) {
      throw const LocalMediaLibraryException('这个项目没有可用的本地播放路径。');
    }
    await _ensureAllowed(path);
    final file = File(path);
    if (!await file.exists()) {
      throw const LocalMediaLibraryException('媒体文件已被移动、删除或当前不可访问。');
    }
    final extension = _extension(path);
    final uri = extension == '.strm'
        ? await _readStrmUri(file)
        : Uri.file(file.absolute.path, windows: Platform.isWindows);
    return PlaybackPlan(
      itemId: item.id,
      mediaSourceId: 'local',
      playSessionId: 'local-${DateTime.now().microsecondsSinceEpoch}',
      streamUri: uri,
      method: PlaybackMethod.directPlay,
      duration: item.runTime,
    );
  }

  Future<MediaItem?> _itemForEntity(FileSystemEntity entity) async {
    final path = entity.path;
    final name = _baseName(path);
    if (name.startsWith('.')) return null;
    if (entity is Directory) {
      final stat = await entity.stat();
      return MediaItem(
        id: _itemId(path),
        name: name,
        kind: MediaItemKind.folder,
        source: MediaItemSource.local,
        sourcePath: path,
        collectionType: 'local-folder',
        imageUri: _findArtworkSync(path, directory: true),
        dateModified: stat.modified,
      );
    }
    if (entity is! File) return null;
    final extension = _extension(path);
    final isVideo = supportedVideoExtensions.contains(extension);
    final isAudio = supportedAudioExtensions.contains(extension);
    if (!isVideo && !isAudio) return null;
    final stat = await entity.stat();
    return MediaItem(
      id: _itemId(path),
      name: _displayName(name),
      kind: isAudio ? MediaItemKind.audio : MediaItemKind.video,
      overview: '来自本地媒体库 · ${entity.absolute.path}',
      productionYear: _readYear(name),
      source: MediaItemSource.local,
      sourcePath: entity.absolute.path,
      imageUri: _findArtworkSync(path),
      fileSize: stat.size,
      dateModified: stat.modified,
    );
  }

  Future<void> _ensureAllowed(String path) async {
    final candidate = _normalizePath(File(path).absolute.path);
    final libraries = await _store.read();
    final allowed = libraries.any((library) {
      final root = _normalizePath(library.path);
      return candidate == root ||
          candidate.startsWith('$root${Platform.pathSeparator}');
    });
    if (!allowed) {
      throw const LocalMediaLibraryException('该路径不属于已添加的本地媒体库。');
    }
  }

  Future<Uri> _readStrmUri(File file) async {
    try {
      final lines = await file.readAsLines();
      String? source;
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isNotEmpty && !line.startsWith('#')) {
          source = line;
          break;
        }
      }
      if (source == null) {
        throw const LocalMediaLibraryException('STRM 文件中没有可用的播放地址。');
      }
      final parsed = Uri.tryParse(source);
      final looksLikeWindowsPath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(source);
      if (!looksLikeWindowsPath && parsed != null && parsed.hasScheme) {
        return parsed;
      }
      final target = File(source).isAbsolute
          ? File(source)
          : File('${file.parent.path}${Platform.pathSeparator}$source');
      return Uri.file(target.absolute.path, windows: Platform.isWindows);
    } on LocalMediaLibraryException {
      rethrow;
    } on FileSystemException {
      throw const LocalMediaLibraryException('无法读取 STRM 文件，请检查文件权限。');
    }
  }
}

bool _matchesKind(MediaItem item, MediaLibraryKindFilter filter) {
  if (item.kind == MediaItemKind.folder) return true;
  return switch (filter) {
    MediaLibraryKindFilter.all => true,
    MediaLibraryKindFilter.movies =>
      item.kind == MediaItemKind.movie || item.kind == MediaItemKind.video,
    MediaLibraryKindFilter.series => item.kind == MediaItemKind.series,
    MediaLibraryKindFilter.episodes => item.kind == MediaItemKind.episode,
  };
}

void _sortItems(List<MediaItem> items, MediaLibrarySort sort) {
  items.sort((left, right) {
    final folderOrder = (left.kind == MediaItemKind.folder ? 0 : 1).compareTo(
      right.kind == MediaItemKind.folder ? 0 : 1,
    );
    if (folderOrder != 0) return folderOrder;
    final compared = switch (sort) {
      MediaLibrarySort.nameAscending => left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      ),
      MediaLibrarySort.dateCreatedDescending => _compareNullableDate(
        right.dateModified,
        left.dateModified,
      ),
      MediaLibrarySort.productionYearDescending =>
        (right.productionYear ?? -1).compareTo(left.productionYear ?? -1),
      MediaLibrarySort.ratingDescending =>
        (right.communityRating ?? -1).compareTo(left.communityRating ?? -1),
    };
    return compared == 0
        ? left.name.toLowerCase().compareTo(right.name.toLowerCase())
        : compared;
  });
}

int _compareNullableDate(DateTime? left, DateTime? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return left.compareTo(right);
}

String _itemId(String path) => 'local-item:${_idForPath(path)}';

String _idForPath(String path) =>
    base64Url.encode(utf8.encode(_normalizePath(path))).replaceAll('=', '');

String _normalizePath(String path) {
  var normalized = File(
    path,
  ).absolute.path.replaceAll(RegExp(r'[\\/]+'), Platform.pathSeparator);
  while (normalized.length > 3 && normalized.endsWith(Platform.pathSeparator)) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

String _extension(String path) {
  final name = _baseName(path);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot).toLowerCase();
}

String _displayName(String fileName) {
  final extension = _extension(fileName);
  final stem = extension.isEmpty
      ? fileName
      : fileName.substring(0, fileName.length - extension.length);
  return stem
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int? _readYear(String value) {
  final matches = RegExp(r'(?<!\d)(19\d{2}|20\d{2})(?!\d)').allMatches(value);
  return matches.isEmpty ? null : int.tryParse(matches.last.group(1)!);
}

Uri? _findArtworkSync(String path, {bool directory = false}) {
  final folder = directory ? Directory(path) : File(path).parent;
  final candidates = <String>[];
  if (!directory) {
    final name = _baseName(path);
    final extension = _extension(name);
    final stem = extension.isEmpty
        ? name
        : name.substring(0, name.length - extension.length);
    for (final imageExtension in const ['.jpg', '.jpeg', '.png', '.webp']) {
      candidates.add(
        '${folder.path}${Platform.pathSeparator}$stem$imageExtension',
      );
    }
  }
  for (final name in const [
    'poster.jpg',
    'folder.jpg',
    'cover.jpg',
    'poster.png',
  ]) {
    candidates.add('${folder.path}${Platform.pathSeparator}$name');
  }
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return Uri.file(
        File(candidate).absolute.path,
        windows: Platform.isWindows,
      );
    }
  }
  return null;
}

class LocalMediaLibraryException implements Exception {
  const LocalMediaLibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}
