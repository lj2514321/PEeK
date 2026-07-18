import 'dart:convert';
import 'dart:math';

import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _activeSessionKey = 'active_server_session_v1';

  Future<void> write({
    required String serverId,
    required String userId,
    required String token,
  }) {
    return _storage.write(key: _key(serverId, userId), value: token);
  }

  Future<String?> read({required String serverId, required String userId}) {
    return _storage.read(key: _key(serverId, userId));
  }

  Future<void> delete({required String serverId, required String userId}) {
    return _storage.delete(key: _key(serverId, userId));
  }

  Future<void> writeSession(AuthenticatedServer account) async {
    await write(
      serverId: account.server.serverId,
      userId: account.userId,
      token: account.accessToken,
    );
    await _storage.write(
      key: _activeSessionKey,
      value: jsonEncode({
        'kind': account.server.kind.name,
        'name': account.server.name,
        'version': account.server.version,
        'serverId': account.server.serverId,
        'apiBaseUri': account.server.apiBaseUri.toString(),
        'userId': account.userId,
        'userName': account.userName,
        'deviceId': account.deviceId,
      }),
    );
  }

  Future<AuthenticatedServer?> readSession() async {
    try {
      final raw = await _storage.read(key: _activeSessionKey);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;

      final serverId = data['serverId'];
      final userId = data['userId'];
      final baseUri = Uri.tryParse('${data['apiBaseUri']}');
      if (serverId is! String ||
          serverId.isEmpty ||
          userId is! String ||
          userId.isEmpty ||
          baseUri == null ||
          !baseUri.hasScheme ||
          (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
        return null;
      }
      final token = await read(serverId: serverId, userId: userId);
      if (token == null || token.isEmpty) return null;

      final kind = data['kind'] == ServerKind.emby.name
          ? ServerKind.emby
          : ServerKind.jellyfin;
      final server = DiscoveredServer(
        kind: kind,
        name: _string(data['name'], kind.label),
        version: _string(data['version'], ''),
        serverId: serverId,
        apiBaseUri: baseUri,
      );
      final storedDeviceId = data['deviceId'];
      final deviceId = storedDeviceId is String && storedDeviceId.isNotEmpty
          ? storedDeviceId
          : await getOrCreateDeviceId();
      return AuthenticatedServer(
        server: server,
        userId: userId,
        userName: _string(data['userName'], '用户'),
        deviceId: deviceId,
        accessToken: token,
      );
    } on Object {
      return null;
    }
  }

  Future<void> clearSession({AuthenticatedServer? account}) async {
    try {
      if (account != null) {
        await delete(serverId: account.server.serverId, userId: account.userId);
      }
    } finally {
      await _storage.delete(key: _activeSessionKey);
    }
  }

  Future<String> getOrCreateDeviceId() async {
    const key = 'client_device_id';
    final existing = await _storage.read(key: key);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _storage.write(key: key, value: id);
    return id;
  }

  String _key(String serverId, String userId) {
    return 'server_token_${serverId}_$userId';
  }

  String _string(Object? value, String fallback) {
    return value is String && value.isNotEmpty ? value : fallback;
  }
}
