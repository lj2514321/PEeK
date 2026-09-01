import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Central cross-platform resolver for the application's persistent storage root directory.
///
/// On Windows, it preserves the existing `%LOCALAPPDATA%\PEeK` path for backward
/// compatibility.
/// On Android, iOS, macOS, and Linux, it uses [path_provider]'s
/// [getApplicationSupportDirectory] or [getApplicationDocumentsDirectory].
abstract final class AppStoragePath {
  static Directory? _cachedDirectory;
  static Directory? overrideDirectory;

  /// Initializes the app storage directory asynchronously before running the app.
  /// Safe to call multiple times.
  static Future<Directory> ensureInitialized() async {
    if (overrideDirectory != null) {
      return overrideDirectory!;
    }
    if (_cachedDirectory != null) {
      return _cachedDirectory!;
    }

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        final dir = Directory('$localAppData${Platform.pathSeparator}PEeK');
        _cachedDirectory = dir;
        return dir;
      }
    }

    try {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory('${supportDir.path}${Platform.pathSeparator}PEeK');
      _cachedDirectory = dir;
      return dir;
    } catch (_) {
      final fallback = _fallbackDirectory();
      _cachedDirectory = fallback;
      return fallback;
    }
  }

  /// Synchronously returns the base storage directory.
  /// Falls back gracefully in test environments without requiring async initialization.
  static Directory get defaultDirectory {
    if (overrideDirectory != null) return overrideDirectory!;
    if (_cachedDirectory != null) return _cachedDirectory!;
    return _fallbackDirectory();
  }

  /// Returns the logs subdirectory.
  static Directory get logsDirectory {
    return Directory('${defaultDirectory.path}${Platform.pathSeparator}logs');
  }

  /// Returns the downloads subdirectory.
  static Directory get downloadsDirectory {
    return Directory(
      '${defaultDirectory.path}${Platform.pathSeparator}Downloads',
    );
  }

  /// Returns the actor favorites subdirectory.
  static Directory get actorFavoritesDirectory {
    return Directory(
      '${defaultDirectory.path}${Platform.pathSeparator}ActorFavorites',
    );
  }

  static Directory _fallbackDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final root = localAppData == null || localAppData.isEmpty
        ? Directory.systemTemp.path
        : localAppData;
    return Directory('$root${Platform.pathSeparator}PEeK');
  }

  /// Resets cached directory (useful for testing).
  static void resetForTest() {
    _cachedDirectory = null;
    overrideDirectory = null;
  }
}
