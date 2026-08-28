import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final duplicateIgnoredStoreProvider = Provider<DuplicateIgnoredStore>((ref) {
  return JsonDuplicateIgnoredStore();
});

abstract interface class DuplicateIgnoredStore {
  Future<Set<String>> read();
  Future<Set<String>> ignore(String groupId);
  Future<Set<String>> unignore(String groupId);
  Future<void> clear();
}

class MemoryDuplicateIgnoredStore implements DuplicateIgnoredStore {
  MemoryDuplicateIgnoredStore([Iterable<String> initial = const []])
      : _ignored = initial.toSet();

  final Set<String> _ignored;

  @override
  Future<Set<String>> read() async => Set.unmodifiable(_ignored);

  @override
  Future<Set<String>> ignore(String groupId) async {
    _ignored.add(groupId);
    return Set.unmodifiable(_ignored);
  }

  @override
  Future<Set<String>> unignore(String groupId) async {
    _ignored.remove(groupId);
    return Set.unmodifiable(_ignored);
  }

  @override
  Future<void> clear() async => _ignored.clear();
}

class JsonDuplicateIgnoredStore implements DuplicateIgnoredStore {
  JsonDuplicateIgnoredStore({Directory? directory})
      : _directory = directory ?? _defaultDirectory();

  final Directory _directory;
  Set<String>? _cached;
  Future<void> _writeQueue = Future.value();

  File get _file =>
      File('${_directory.path}${Platform.pathSeparator}dedupe_ignored_v1.json');

  static Directory _defaultDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? Directory.systemTemp.path
        : localAppData;
    return Directory('$root${Platform.pathSeparator}PEeK');
  }

  @override
  Future<Set<String>> read() async => Set.unmodifiable(await _load());

  @override
  Future<Set<String>> ignore(String groupId) async {
    final current = await _load();
    current.add(groupId);
    _cached = current;
    await _persist(current);
    return Set.unmodifiable(current);
  }

  @override
  Future<Set<String>> unignore(String groupId) async {
    final current = await _load();
    current.remove(groupId);
    _cached = current;
    await _persist(current);
    return Set.unmodifiable(current);
  }

  @override
  Future<void> clear() async {
    _cached = <String>{};
    await _persist(<String>{});
  }

  Future<Set<String>> _load() async {
    final inMemory = _cached;
    if (inMemory != null) return inMemory;

    try {
      if (!await _file.exists()) {
        _cached = <String>{};
        return _cached!;
      }
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) {
        _cached = <String>{};
        return _cached!;
      }
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded.whereType<String>().toSet();
        _cached = list;
        return list;
      }
    } catch (_) {
      // Fallback on corrupt file
    }
    _cached = <String>{};
    return _cached!;
  }

  Future<void> _persist(Set<String> items) {
    _writeQueue = _writeQueue.then((_) async {
      try {
        if (!await _directory.exists()) {
          await _directory.create(recursive: true);
        }
        final tempFile = File('${_file.path}.tmp');
        await tempFile.writeAsString(jsonEncode(items.toList()));
        if (await _file.exists()) {
          await _file.delete();
        }
        await tempFile.rename(_file.path);
      } catch (_) {
        // Suppress disk write failures
      }
    });
    return _writeQueue;
  }
}
