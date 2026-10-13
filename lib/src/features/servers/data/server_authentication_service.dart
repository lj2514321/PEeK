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
      final authHeader = _authorizationHeader(server.kind, deviceId);
      final mediaBrowserHeader = _authorizationHeader(
        ServerKind.jellyfin,
        deviceId,
      );
      final response = await _dio.postUri<Map<String, dynamic>>(
        _appendPath(server.apiBaseUri, 'Users/AuthenticateByName'),
        data: {'Username': normalizedUsername, 'Pw': password},
        options: Options(
          contentType: Headers.jsonContentType,
          headers: {
            'Authorization': authHeader,
            'X-Emby-Authorization': authHeader,
            'X-MediaBrowser-Authorization': mediaBrowserHeader,
          },
        ),
      );

      final data = response.data;
      final user = data?['User'];
      final token = data?['AccessToken'];
      if (data == null || user is! Map || token is! String || token.isEmpty) {
        throw const ServerAuthenticationException('服务器返回了无法识别的登录结果。');
      }

      final userId = user['Id']?.toString();
      if (userId == null || userId.isEmpty) {
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
      final responseData = error.response?.data;
      String? detail;
      if (responseData is Map && responseData['Message'] is String) {
        detail = (responseData['Message'] as String).trim();
      } else if (responseData is String && responseData.trim().isNotEmpty) {
        detail = responseData.trim();
      }

      if (statusCode == 401) {
        if (detail != null && detail.isNotEmpty) {
          throw ServerAuthenticationException('登录认证失败（401）：$detail');
        }
        throw const ServerAuthenticationException(
          '用户名或密码不正确（401）。若确认凭据无误，请检查服务端是否触发了防暴力破解临时锁定（可稍候15分钟后重试）。',
        );
      }
      if (statusCode == 403) {
        if (detail != null && detail.isNotEmpty) {
          throw ServerAuthenticationException('登录受限（403）：$detail');
        }
        throw const ServerAuthenticationException('账号访问受限（403），请检查服务器用户登录权限。');
      }
      if (statusCode == 400) {
        if (detail != null && detail.isNotEmpty) {
          throw ServerAuthenticationException('登录请求错误（400）：$detail');
        }
        throw const ServerAuthenticationException('登录请求参数错误（400），请核对用户名。');
      }
      final msg = error.message ?? error.toString();
      throw ServerAuthenticationException(
        '无法完成登录${statusCode != null ? "（HTTP $statusCode）" : ""}。请检查服务器状态和网络连接：$msg',
      );
    } on ServerAuthenticationException {
      rethrow;
    } catch (error) {
      throw ServerAuthenticationException('登录过程发生异常：$error');
    }
  }

  Future<AuthenticatedServer?> restoreSession() {
    return _tokenStore.readSession();
  }

  Future<ServerAccountState> restoreSessionState() {
    return _tokenStore.readSessionState();
  }

  Future<void> activate(AuthenticatedServer account) {
    return _tokenStore.activateSession(account);
  }

  Future<void> logout(AuthenticatedServer account) {
    return _tokenStore.signOut(account);
  }

  Future<void> remove(ServerProfile profile) {
    return _tokenStore.removeProfile(profile);
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
