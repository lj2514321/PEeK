import 'dart:io';

import 'package:embyplayer/src/core/storage/app_storage_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppStoragePath', () {
    setUp(() {
      AppStoragePath.overrideDirectory = null;
    });

    tearDown(() {
      AppStoragePath.overrideDirectory = null;
    });

    test('defaultDirectory returns a non-empty directory path', () {
      final dir = AppStoragePath.defaultDirectory;
      expect(dir.path, isNotEmpty);
    });

    test('logsDirectory, downloadsDirectory, and actorFavoritesDirectory are subdirectories', () {
      final root = AppStoragePath.defaultDirectory;
      final logs = AppStoragePath.logsDirectory;
      final downloads = AppStoragePath.downloadsDirectory;
      final favorites = AppStoragePath.actorFavoritesDirectory;

      expect(logs.path.startsWith(root.path), isTrue);
      expect(logs.path.endsWith('logs'), isTrue);
      expect(downloads.path.startsWith(root.path), isTrue);
      expect(downloads.path.endsWith('Downloads'), isTrue);
      expect(favorites.path.startsWith(root.path), isTrue);
      expect(favorites.path.endsWith('ActorFavorites'), isTrue);
    });

    test('overrideDirectory overrides all resolved paths and can be reset', () {
      final tempDir = Directory.systemTemp.createTempSync('app_storage_test');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
        AppStoragePath.overrideDirectory = null;
      });

      AppStoragePath.overrideDirectory = tempDir;
      expect(AppStoragePath.defaultDirectory.path, tempDir.path);
      expect(AppStoragePath.logsDirectory.path, '${tempDir.path}${Platform.pathSeparator}logs');

      AppStoragePath.overrideDirectory = null;
      expect(AppStoragePath.defaultDirectory.path, isNot(tempDir.path));
    });

    test('ensureInitialized resolves without throwing', () async {
      await expectLater(AppStoragePath.ensureInitialized(), completes);
    });
  });
}
