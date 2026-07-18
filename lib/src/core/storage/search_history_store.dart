import 'dart:convert';
import 'dart:io';

abstract interface class SearchHistoryStore {
  Future<List<String>> read();

  Future<List<String>> add(String query);

  Future<void> clear();
}

class MemorySearchHistoryStore implements SearchHistoryStore {
  MemorySearchHistoryStore([Iterable<String> initial = const []])
    : _queries = initial.toList();

  List<String> _queries;

  @override
  Future<List<String>> read() async => List.unmodifiable(_queries);

  @override
  Future<List<String>> add(String query) async {
    _queries = _updatedQueries(_queries, query);
    return List.unmodifiable(_queries);
  }

  @override
  Future<void> clear() async => _queries = [];
}

class JsonSearchHistoryStore implements SearchHistoryStore {
  JsonSearchHistoryStore({Directory? directory})
    : _directory = directory ?? _defaultDirectory();

  final Directory _directory;
  List<String>? _queries;
  Future<void> _writeQueue = Future.value();

  File get _file =>
      File('${_directory.path}${Platform.pathSeparator}search_history_v1.json');

  static Directory _defaultDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? Directory.systemTemp.path
        : localAppData;
    return Directory('$root${Platform.pathSeparator}PEeK');
  }

  @override
  Future<List<String>> read() async => List.unmodifiable(await _load());

  @override
  Future<List<String>> add(String query) async {
    final current = await _load();
    final updated = _updatedQueries(current, query);
    _queries = updated;
    await _persist(updated);
    return List.unmodifiable(updated);
  }

  @override
  Future<void> clear() async {
    _queries = [];
    await _persist(const []);
  }

  Future<List<String>> _load() async {
    final loaded = _queries;
    if (loaded != null) return loaded;
    try {
      if (await _file.exists()) {
        final data = jsonDecode(await _file.readAsString());
        final rawQueries = data is Map ? data['queries'] : null;
        if (rawQueries is List) {
          return _queries = rawQueries
              .whereType<String>()
              .where((item) => item.trim().isNotEmpty)
              .take(8)
              .toList();
        }
      }
    } on FileSystemException {
      // Search history is optional and must never block the search page.
    } on FormatException {
      // Ignore a partial or outdated history file.
    }
    return _queries = [];
  }

  Future<void> _persist(List<String> queries) {
    final snapshot = jsonEncode({'version': 1, 'queries': queries});
    _writeQueue = _writeQueue.catchError((_) {}).then((_) async {
      try {
        await _directory.create(recursive: true);
        await _file.writeAsString(snapshot, flush: true);
      } on FileSystemException {
        // Search remains usable if history cannot be written.
      }
    });
    return _writeQueue;
  }
}

List<String> _updatedQueries(Iterable<String> current, String query) {
  final normalized = query.trim();
  if (normalized.isEmpty) return current.toList();
  final lower = normalized.toLowerCase();
  return [
    normalized,
    ...current.where((item) => item.toLowerCase() != lower),
  ].take(8).toList();
}
