import 'dart:convert';
import 'dart:io';

import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/storage/app_storage_path.dart';
import 'package:embyplayer/src/features/scrobble/domain/bangumi_profile.dart';

class BangumiStore {
  BangumiStore({Directory? directory})
    : _directory = directory ?? AppStoragePath.defaultDirectory,
      _isDefaultDirectory = directory == null;

  final Directory _directory;
  final bool _isDefaultDirectory;

  static bool _hasCachedDefaultProfile = false;
  static BangumiProfile? _cachedDefaultProfile;

  bool get hasMemoryCachedProfile =>
      !AppMotion.isTest && _isDefaultDirectory && _hasCachedDefaultProfile;

  BangumiProfile? get memoryCachedProfile => _cachedDefaultProfile;

  static Future<void> prewarm() async {
    if (AppMotion.isTest || _hasCachedDefaultProfile) return;
    await BangumiStore().readProfile();
  }

  File get _file => File(
    '${_directory.path}${Platform.pathSeparator}bangumi_profile_v1.json',
  );

  Future<BangumiProfile?> readProfile() async {
    if (!AppMotion.isTest && _isDefaultDirectory && _hasCachedDefaultProfile) {
      return _cachedDefaultProfile;
    }
    try {
      final file = _file;
      if (!await file.exists()) {
        if (!AppMotion.isTest && _isDefaultDirectory) {
          _cachedDefaultProfile = null;
          _hasCachedDefaultProfile = true;
        }
        return null;
      }
      final content = await file.readAsString();
      final map = jsonDecode(content);
      if (map is Map<String, dynamic>) {
        final profile = BangumiProfile.fromJson(map);
        if (!AppMotion.isTest && _isDefaultDirectory) {
          _cachedDefaultProfile = profile;
          _hasCachedDefaultProfile = true;
        }
        return profile;
      }
    } catch (_) {}
    if (!AppMotion.isTest && _isDefaultDirectory) {
      _cachedDefaultProfile = null;
      _hasCachedDefaultProfile = true;
    }
    return null;
  }

  Future<void> saveProfile(BangumiProfile profile) async {
    if (!AppMotion.isTest && _isDefaultDirectory) {
      _cachedDefaultProfile = profile;
      _hasCachedDefaultProfile = true;
    }
    try {
      final file = _file;
      if (!await _directory.exists()) {
        await _directory.create(recursive: true);
      }
      await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
    } catch (_) {}
  }

  Future<void> clearProfile() async {
    if (!AppMotion.isTest && _isDefaultDirectory) {
      _cachedDefaultProfile = null;
      _hasCachedDefaultProfile = true;
    }
    try {
      final file = _file;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
