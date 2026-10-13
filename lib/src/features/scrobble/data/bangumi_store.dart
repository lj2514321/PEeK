import 'dart:convert';
import 'dart:io';

import 'package:embyplayer/src/core/storage/app_storage_path.dart';
import 'package:embyplayer/src/features/scrobble/domain/bangumi_profile.dart';

class BangumiStore {
  BangumiStore({Directory? directory})
    : _directory = directory ?? AppStoragePath.defaultDirectory;

  final Directory _directory;

  File get _file => File(
    '${_directory.path}${Platform.pathSeparator}bangumi_profile_v1.json',
  );

  Future<BangumiProfile?> readProfile() async {
    try {
      final file = _file;
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final map = jsonDecode(content);
      if (map is Map<String, dynamic>) {
        return BangumiProfile.fromJson(map);
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveProfile(BangumiProfile profile) async {
    try {
      final file = _file;
      if (!await _directory.exists()) {
        await _directory.create(recursive: true);
      }
      await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
    } catch (_) {}
  }

  Future<void> clearProfile() async {
    try {
      final file = _file;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
