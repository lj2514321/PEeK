import 'dart:convert';
import 'dart:math';

import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, String> _memoryFallback = {};

  static const _legacyActiveSessionKey = 'active_server_session_v1';
  static const _accountDirectoryKey = 'server_account_directory_v2';
  static const _activeProfileKey = 'active_server_profile_v2';

  Future<String?> _safeRead(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) _memoryFallback[key] = value;
      return value ?? _memoryFallback[key];
    } catch (_) {
      return _memoryFallback[key];
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    _memoryFallback[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  Future<void> _safeDelete(String key) async {
    _memoryFallback.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }

  Future<void> write({
    required String serverId,
    required String userId,
    required String token,
  }) {
    return _safeWrite(_tokenKey(serverId, userId), token);
  }

  Future<String?> read({required String serverId, required String userId}) {
    return _safeRead(_tokenKey(serverId, userId));
  }

  Future<void> delete({required String serverId, required String userId}) {
    return _safeDelete(_tokenKey(serverId, userId));
  }

  Future<void> writeSession(AuthenticatedServer account) async {
    await write(
      serverId: account.server.serverId,
      userId: account.userId,
      token: account.accessToken,
    );
    final profiles = await _readProfilesWithMigration();
    final profile = ServerProfile.fromSession(account);
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index == -1) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    await _writeProfiles(profiles);
    await _safeWrite(_activeProfileKey, profile.id);
    await _safeDelete(_legacyActiveSessionKey);
  }

  Future<ServerAccountState> readSessionState() async {
    try {
      final profiles = await _readProfilesWithMigration();
      final activeProfileId = await _safeRead(_activeProfileKey);
      final accounts = <ServerAccountEntry>[];
      AuthenticatedServer? activeSession;

      for (final profile in profiles) {
        final token = await read(
          serverId: profile.serverId,
          userId: profile.userId,
        );
        final session = token == null || token.isEmpty
            ? null
            : AuthenticatedServer(
                server: profile.server,
                userId: profile.userId,
                userName: profile.userName,
                deviceId: profile.deviceId,
                accessToken: token,
              );
        accounts.add(ServerAccountEntry(profile: profile, session: session));
        if (profile.id == activeProfileId) activeSession = session;
      }

      return ServerAccountState(
        accounts: List.unmodifiable(accounts),
        activeSession: activeSession,
      );
    } on Object {
      return const ServerAccountState();
    }
  }

  Future<AuthenticatedServer?> readSession() async {
    return (await readSessionState()).activeSession;
  }

  Future<List<AuthenticatedServer>> readSessions() async {
    final state = await readSessionState();
    return state.accounts
        .map((entry) => entry.session)
        .whereType<AuthenticatedServer>()
        .toList(growable: false);
  }

  Future<void> activateSession(AuthenticatedServer account) async {
    final token = await read(
      serverId: account.server.serverId,
      userId: account.userId,
    );
    if (token == null || token.isEmpty) {
      throw StateError('Cannot activate a signed-out server account.');
    }
    final profiles = await _readProfilesWithMigration();
    final profile = ServerProfile.fromSession(account);
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index == -1) {
      profiles.add(profile);
      await _writeProfiles(profiles);
    } else if (!_sameProfile(profiles[index], profile)) {
      profiles[index] = profile;
      await _writeProfiles(profiles);
    }
    await _safeWrite(_activeProfileKey, profile.id);
  }

  Future<void> signOut(AuthenticatedServer account) async {
    await _readProfilesWithMigration();
    try {
      await delete(serverId: account.server.serverId, userId: account.userId);
    } finally {
      final activeProfileId = await _safeRead(_activeProfileKey);
      if (activeProfileId == account.profileId) {
        await _safeDelete(_activeProfileKey);
      }
      await _safeDelete(_legacyActiveSessionKey);
    }
  }

  Future<void> removeProfile(ServerProfile profile) async {
    final profiles = await _readProfilesWithMigration();
    profiles.removeWhere((item) => item.id == profile.id);
    try {
      await delete(serverId: profile.serverId, userId: profile.userId);
    } finally {
      await _writeProfiles(profiles);
      final activeProfileId = await _safeRead(_activeProfileKey);
      if (activeProfileId == profile.id) {
        await _safeDelete(_activeProfileKey);
      }
      await _safeDelete(_legacyActiveSessionKey);
    }
  }

  Future<void> clearSession({AuthenticatedServer? account}) async {
    if (account == null) {
      await _safeDelete(_activeProfileKey);
      await _safeDelete(_legacyActiveSessionKey);
      return;
    }
    await signOut(account);
  }

  Future<String> getOrCreateDeviceId() async {
    const key = 'client_device_id';
    final existing = await _safeRead(key);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _safeWrite(key, id);
    return id;
  }

  Future<List<ServerProfile>> _readProfilesWithMigration() async {
    final raw = await _safeRead(_accountDirectoryKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        return _decodeProfiles(raw);
      } on FormatException {
        return <ServerProfile>[];
      } catch (_) {
        return <ServerProfile>[];
      }
    }

    final legacy = await _readLegacyProfile();
    if (legacy == null) return <ServerProfile>[];
    await _writeProfiles([legacy]);
    await _safeWrite(_activeProfileKey, legacy.id);
    await _safeDelete(_legacyActiveSessionKey);
    return [legacy];
  }

  Future<ServerProfile?> _readLegacyProfile() async {
    final raw = await _safeRead(_legacyActiveSessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final deviceId = _string(decoded['deviceId'], await getOrCreateDeviceId());
      return _profileFromJson({...decoded, 'deviceId': deviceId});
    } catch (_) {
      return null;
    }
  }

  List<ServerProfile> _decodeProfiles(String raw) {
    try {
      final decoded = jsonDecode(raw);
      final values = decoded is Map<String, dynamic> ? decoded['profiles'] : null;
      if (values is! List) return <ServerProfile>[];
      return values
          .whereType<Map<String, dynamic>>()
          .map(_profileFromJson)
          .whereType<ServerProfile>()
          .toList(growable: true);
    } catch (_) {
      return <ServerProfile>[];
    }
  }

  ServerProfile? _profileFromJson(Map<String, dynamic> data) {
    final serverId = _string(data['serverId'], '');
    final userId = _string(data['userId'], '');
    final apiBaseUri = Uri.tryParse('${data['apiBaseUri']}');
    if (serverId.isEmpty ||
        userId.isEmpty ||
        apiBaseUri == null ||
        !apiBaseUri.hasScheme ||
        (apiBaseUri.scheme != 'http' && apiBaseUri.scheme != 'https')) {
      return null;
    }
    final kind = data['kind'] == ServerKind.emby.name
        ? ServerKind.emby
        : ServerKind.jellyfin;
    return ServerProfile(
      id: serverProfileId(serverId, userId),
      kind: kind,
      name: _string(data['name'], kind.label),
      version: _string(data['version'], ''),
      apiBaseUri: apiBaseUri,
      serverId: serverId,
      userId: userId,
      userName: _string(data['userName'], '用户'),
      deviceId: _string(data['deviceId'], ''),
    );
  }

  Future<void> _writeProfiles(List<ServerProfile> profiles) {
    return _safeWrite(
      _accountDirectoryKey,
      jsonEncode({
        'version': 2,
        'profiles': [for (final profile in profiles) _profileJson(profile)],
      }),
    );
  }

  Map<String, String> _profileJson(ServerProfile profile) {
    return {
      'id': profile.id,
      'kind': profile.kind.name,
      'name': profile.name,
      'version': profile.version,
      'apiBaseUri': profile.apiBaseUri.toString(),
      'serverId': profile.serverId,
      'userId': profile.userId,
      'userName': profile.userName,
      'deviceId': profile.deviceId,
    };
  }

  bool _sameProfile(ServerProfile first, ServerProfile second) {
    return first.id == second.id &&
        first.kind == second.kind &&
        first.name == second.name &&
        first.version == second.version &&
        first.apiBaseUri == second.apiBaseUri &&
        first.userName == second.userName &&
        first.deviceId == second.deviceId;
  }

  String _tokenKey(String serverId, String userId) {
    return 'server_token_${serverId}_$userId';
  }

  String _string(Object? value, String fallback) {
    return value is String && value.isNotEmpty ? value : fallback;
  }
}
