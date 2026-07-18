import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/storage/secure_token_store.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

class ServerAuthenticationService {
  ServerAuthenticationService(this._dio, this._tokenStore);

  final Dio _dio;
  final SecureTokenStore _tokenStore;

  Future<AuthenticatedServer> login({
    required DiscoveredServer server,
    required String username,
    required String password,
  }) async {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty) {
      throw const ServerAuthenticationException('请输入用户名。');
    }

    final deviceId = await _tokenStore.getOrCreateDeviceId();

    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        _appendPath(server.apiBaseUri, 'Users/AuthenticateByName'),
        data: {'Username': normalizedUsername, 'Pw': password},
        options: Options(
          contentType: Headers.jsonContentType,
          headers: {
            'X-Emby-Authorization': _authorizationHeader(server.kind, deviceId),
          },
        ),
      );

      final data = response.data;
      final user = data?['User'];
      final token = data?['AccessToken'];
      if (data == null ||
          user is! Map<String, dynamic> ||
          token is! String ||
          token.isEmpty) {
        throw const ServerAuthenticationException('服务器返回了无法识别的登录结果。');
      }

      final userId = user['Id'];
      if (userId is! String || userId.isEmpty) {
        throw const ServerAuthenticationException('登录结果中缺少用户标识。');
      }

      final responseServerId = data['ServerId'];
      final serverId = responseServerId is String && responseServerId.isNotEmpty
          ? responseServerId
          : server.serverId;
      final userName = user['Name'];
      final resolvedServer = server.serverId == serverId
          ? server
          : DiscoveredServer(
              kind: server.kind,
              name: server.name,
              version: server.version,
              serverId: serverId,
              apiBaseUri: server.apiBaseUri,
            );
      final account = AuthenticatedServer(
        server: resolvedServer,
        userId: userId,
        userName: userName is String && userName.isNotEmpty
            ? userName
            : normalizedUsername,
        deviceId: deviceId,
        accessToken: token,
      );
      await _tokenStore.writeSession(account);
      return account;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 400 || statusCode == 401 || statusCode == 403) {
        throw const ServerAuthenticationException('用户名或密码不正确。');
      }
      throw const ServerAuthenticationException('无法完成登录。请检查服务器状态和网络连接。');
    }
  }

  Future<AuthenticatedServer?> restoreSession() {
    return _tokenStore.readSession();
  }

  Future<void> logout(AuthenticatedServer account) {
    return _tokenStore.clearSession(account: account);
  }

  Uri _appendPath(Uri base, String path) {
    return base.replace(
      pathSegments: [...base.pathSegments, ...path.split('/')],
    );
  }

  String _authorizationHeader(ServerKind kind, String deviceId) {
    final scheme = kind == ServerKind.jellyfin ? 'MediaBrowser' : 'Emby';
    return '$scheme Client="PEeK", '
        'Device="Windows", DeviceId="$deviceId", Version="0.1.0"';
  }
}

class ServerAuthenticationException implements Exception {
  const ServerAuthenticationException(this.message);

  final String message;

  @override
  String toString() => message;
}
