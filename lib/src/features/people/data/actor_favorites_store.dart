import 'dart:convert';
import 'dart:io';

import 'package:embyplayer/src/core/storage/app_storage_path.dart';
import 'package:embyplayer/src/features/people/domain/actor_favorite.dart';
import 'package:flutter/foundation.dart';

abstract class ActorFavoritesStore {
  Future<List<ActorFavorite>> readFavorites();
  Future<void> writeFavorites(List<ActorFavorite> favorites);
}

class MemoryActorFavoritesStore implements ActorFavoritesStore {
  MemoryActorFavoritesStore([List<ActorFavorite>? initial])
      : _favorites = List.from(initial ?? const []);

  final List<ActorFavorite> _favorites;

  @override
  Future<List<ActorFavorite>> readFavorites() async => List.unmodifiable(_favorites);

  @override
  Future<void> writeFavorites(List<ActorFavorite> favorites) async {
    _favorites
      ..clear()
      ..addAll(favorites);
  }
}

class LocalActorFavoritesStore implements ActorFavoritesStore {
  LocalActorFavoritesStore([String? filePath])
      : _filePathOverride = filePath;

  final String? _filePathOverride;

  Future<File> get _file async {
    if (_filePathOverride != null) return File(_filePathOverride);
    final dir = AppStoragePath.actorFavoritesDirectory;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}favorites.json');
  }

  @override
  Future<List<ActorFavorite>> readFavorites() async {
    try {
      final target = await _file;
      if (!await target.exists()) return const [];
      final content = await target.readAsString();
      if (content.trim().isEmpty) return const [];
      final raw = jsonDecode(content);
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map((item) => ActorFavorite.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } on Object catch (e) {
      debugPrint('Failed to read actor favorites: $e');
      return const [];
    }
  }

  @override
  Future<void> writeFavorites(List<ActorFavorite> favorites) async {
    try {
      final target = await _file;
      final payload = favorites.map((f) => f.toJson()).toList();
      await target.writeAsString(jsonEncode(payload), flush: true);
    } on Object catch (e) {
      debugPrint('Failed to write actor favorites: $e');
    }
  }
}
