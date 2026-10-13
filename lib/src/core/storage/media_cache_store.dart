import 'dart:convert';
import 'dart:io';

import 'package:embyplayer/src/core/storage/app_storage_path.dart';

class MediaCacheEntry {
  const MediaCacheEntry({required this.storedAt, required this.payload});

  final DateTime storedAt;
  final Map<String, dynamic> payload;
}

abstract interface class MediaCacheStore {
  Future<MediaCacheEntry?> read(String key, {Duration? maxAge});

  Future<void> write(String key, Map<String, dynamic> payload);

  Future<void> clear({bool preserveRecommendations = false});
}

bool _isRecommendationCacheKey(String key) =>
    key.contains('/Items/Suggestions?') || key.contains('SortBy=Random');

class MemoryMediaCacheStore implements MediaCacheStore {
  MemoryMediaCacheStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, MediaCacheEntry> _entries = {};

  @override
  Future<MediaCacheEntry?> read(String key, {Duration? maxAge}) async {
    final entry = _entries[key];
    if (entry == null) return null;
    if (maxAge != null && _clock().difference(entry.storedAt) > maxAge) {
      return null;
    }
    return entry;
  }

  @override
  Future<void> write(String key, Map<String, dynamic> payload) async {
    _entries[key] = MediaCacheEntry(
      storedAt: _clock(),
      payload: Map<String, dynamic>.from(payload),
    );
  }

  @override
  Future<void> clear({bool preserveRecommendations = false}) async {
    if (preserveRecommendations) {
      _entries.removeWhere((key, _) => !_isRecommendationCacheKey(key));
    } else {
      _entries.clear();
    }
  }
}

class JsonFileMediaCacheStore implements MediaCacheStore {
  JsonFileMediaCacheStore({
    Directory? directory,
    DateTime Function()? clock,
    this.maxEntries = 180,
  }) : _directory = directory ?? _defaultDirectory(),
       _clock = clock ?? DateTime.now;

  final Directory _directory;
  final DateTime Function() _clock;
  final int maxEntries;

  Map<String, MediaCacheEntry>? _entries;
  Future<Map<String, MediaCacheEntry>>? _loadFuture;
  Future<void> _writeQueue = Future.value();

  File get _file =>
      File('${_directory.path}${Platform.pathSeparator}media_cache_v1.json');

  static Directory _defaultDirectory() => AppStoragePath.defaultDirectory;

  @override
  Future<MediaCacheEntry?> read(String key, {Duration? maxAge}) async {
    final entries = await _load();
    final entry = entries[key];
    if (entry == null) return null;
    if (maxAge != null && _clock().difference(entry.storedAt) > maxAge) {
      return null;
    }
    return entry;
  }

  @override
  Future<void> write(String key, Map<String, dynamic> payload) async {
    final entries = await _load();
    entries[key] = MediaCacheEntry(
      storedAt: _clock(),
      payload: Map<String, dynamic>.from(payload),
    );
    if (entries.length > maxEntries) {
      final oldest = entries.entries.toList()
        ..sort((a, b) => a.value.storedAt.compareTo(b.value.storedAt));
      for (final entry in oldest.take(entries.length - maxEntries)) {
        entries.remove(entry.key);
      }
    }
    await _persist(entries);
  }

  @override
  Future<void> clear({bool preserveRecommendations = false}) async {
    final entries = await _load();
    if (preserveRecommendations) {
      entries.removeWhere((key, _) => !_isRecommendationCacheKey(key));
    } else {
      entries.clear();
    }
    await _persist(entries);
  }

  Future<Map<String, MediaCacheEntry>> _load() {
    final loaded = _entries;
    if (loaded != null) return Future.value(loaded);
    return _loadFuture ??= _loadFromDisk();
  }

  Future<Map<String, MediaCacheEntry>> _loadFromDisk() async {
    final entries = <String, MediaCacheEntry>{};
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        final rawEntries = decoded is Map ? decoded['entries'] : null;
        if (rawEntries is Map) {
          for (final item in rawEntries.entries) {
            final value = item.value;
            if (item.key is! String || value is! Map) continue;
            final storedAt = DateTime.tryParse('${value['storedAt']}');
            final payload = value['payload'];
            if (storedAt == null || payload is! Map) continue;
            entries[item.key as String] = MediaCacheEntry(
              storedAt: storedAt,
              payload: Map<String, dynamic>.from(payload),
            );
          }
        }
      }
    } on FileSystemException {
      // Cache failures must never prevent the media library from loading.
    } on FormatException {
      // Ignore a partial or outdated cache file and rebuild it on next write.
    }
    _entries = entries;
    return entries;
  }

  Future<void> _persist(Map<String, MediaCacheEntry> entries) {
    final snapshot = jsonEncode({
      'version': 1,
      'entries': {
        for (final entry in entries.entries)
          entry.key: {
            'storedAt': entry.value.storedAt.toUtc().toIso8601String(),
            'payload': entry.value.payload,
          },
      },
    });
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      await _directory.create(recursive: true);
      await _file.writeAsString(snapshot, flush: true);
    });
    return _writeQueue;
  }
}
