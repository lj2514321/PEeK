import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/storage/secure_token_store.dart';
import 'package:embyplayer/src/features/servers/data/server_authentication_service.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingSecureStorage extends FlutterSecureStorage {
  const FailingSecureStorage();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw Exception('Windows Credential Manager simulated failure');
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw Exception('Windows Credential Manager simulated failure');
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw Exception('Windows Credential Manager simulated failure');
  }
}

void main() {
  group('ServerAuthenticationService', () {
    test('sends standard Authorization header for Jellyfin server', () async {
      Map<String, dynamic>? interceptedHeaders;
      dynamic interceptedBody;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              interceptedHeaders = options.headers;
              interceptedBody = options.data;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'AccessToken': 'mock-token-xyz',
                    'ServerId': 'jellyfin-server-id',
                    'User': {'Id': 'user-guid-123', 'Name': 'Alice'},
                  },
                ),
              );
            },
          ),
        );

      final tokenStore = SecureTokenStore(const FailingSecureStorage());
      final service = ServerAuthenticationService(dio, tokenStore);

      final server = DiscoveredServer(
        kind: ServerKind.jellyfin,
        name: 'My Jellyfin',
        version: '10.10.3',
        serverId: 'jellyfin-server-id',
        apiBaseUri: Uri.parse('http://192.168.1.100:8096'),
      );

      final account = await service.login(
        server: server,
        username: 'Alice',
        password: 'secretpassword',
      );

      expect(account.userId, 'user-guid-123');
      expect(account.userName, 'Alice');
      expect(account.accessToken, 'mock-token-xyz');

      // Verify request payload
      expect(interceptedBody, {'Username': 'Alice', 'Pw': 'secretpassword'});

      // Verify headers include both Authorization and X-Emby-Authorization
      expect(interceptedHeaders, isNotNull);
      final authHeader = interceptedHeaders!['Authorization'] as String?;
      expect(authHeader, isNotNull);
      expect(authHeader, contains('MediaBrowser Client="PEeK"'));
      expect(authHeader, contains('Device="Windows"'));
      expect(authHeader, contains('DeviceId='));
      expect(authHeader, contains('Version="0.1.0"'));

      final legacyHeader =
          interceptedHeaders!['X-Emby-Authorization'] as String?;
      expect(legacyHeader, isNotNull);
      expect(legacyHeader, contains('MediaBrowser'));

      final mediaBrowserHeader =
          interceptedHeaders!['X-MediaBrowser-Authorization'] as String?;
      expect(mediaBrowserHeader, isNotNull);
    });

    test('sends standard Authorization header for Emby server', () async {
      Map<String, dynamic>? interceptedHeaders;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              interceptedHeaders = options.headers;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'AccessToken': 'emby-token-abc',
                    'ServerId': 'emby-server-id',
                    'User': {'Id': 'user-emby-456', 'Name': 'Bob'},
                  },
                ),
              );
            },
          ),
        );

      final tokenStore = SecureTokenStore(const FailingSecureStorage());
      final service = ServerAuthenticationService(dio, tokenStore);

      final server = DiscoveredServer(
        kind: ServerKind.emby,
        name: 'My Emby',
        version: '4.8.8.0',
        serverId: 'emby-server-id',
        apiBaseUri: Uri.parse('http://192.168.1.101:8096'),
      );

      final account = await service.login(
        server: server,
        username: 'Bob',
        password: 'pass',
      );

      expect(account.userId, 'user-emby-456');
      final authHeader = interceptedHeaders!['Authorization'] as String?;
      expect(authHeader, contains('Emby Client="PEeK"'));
    });

    test('401 error with server message returns parsed message', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 401,
                    data: {
                      'Message':
                          'User is temporarily locked out due to too many failed attempts.',
                    },
                  ),
                ),
              );
            },
          ),
        );

      final tokenStore = SecureTokenStore(const FailingSecureStorage());
      final service = ServerAuthenticationService(dio, tokenStore);
      final server = DiscoveredServer(
        kind: ServerKind.jellyfin,
        name: 'Test',
        version: '10.10.0',
        serverId: 'test',
        apiBaseUri: Uri.parse('http://127.0.0.1:8096'),
      );

      expect(
        () => service.login(server: server, username: 'test', password: '123'),
        throwsA(
          isA<ServerAuthenticationException>().having(
            (e) => e.message,
            'message',
            contains('User is temporarily locked out'),
          ),
        ),
      );
    });

    test(
      '401 error without server message includes brute force reminder',
      () async {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 401,
                      data: null,
                    ),
                  ),
                );
              },
            ),
          );

        final tokenStore = SecureTokenStore(const FailingSecureStorage());
        final service = ServerAuthenticationService(dio, tokenStore);
        final server = DiscoveredServer(
          kind: ServerKind.jellyfin,
          name: 'Test',
          version: '10.10.0',
          serverId: 'test',
          apiBaseUri: Uri.parse('http://127.0.0.1:8096'),
        );

        expect(
          () =>
              service.login(server: server, username: 'test', password: '123'),
          throwsA(
            isA<ServerAuthenticationException>().having(
              (e) => e.message,
              'message',
              contains('防暴力破解临时锁定'),
            ),
          ),
        );
      },
    );

    test('403 error informs user about restricted account', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 403,
                    data: {'Message': 'Account is disabled.'},
                  ),
                ),
              );
            },
          ),
        );

      final tokenStore = SecureTokenStore(const FailingSecureStorage());
      final service = ServerAuthenticationService(dio, tokenStore);
      final server = DiscoveredServer(
        kind: ServerKind.jellyfin,
        name: 'Test',
        version: '10.10.0',
        serverId: 'test',
        apiBaseUri: Uri.parse('http://127.0.0.1:8096'),
      );

      expect(
        () => service.login(server: server, username: 'test', password: '123'),
        throwsA(
          isA<ServerAuthenticationException>().having(
            (e) => e.message,
            'message',
            contains('Account is disabled'),
          ),
        ),
      );
    });

    test(
      'SecureTokenStore recovers in-memory when FlutterSecureStorage throws',
      () async {
        final store = SecureTokenStore(const FailingSecureStorage());
        final deviceId = await store.getOrCreateDeviceId();
        expect(deviceId, isNotEmpty);

        // Verify that calling getOrCreateDeviceId again returns the cached memory fallback ID
        final deviceId2 = await store.getOrCreateDeviceId();
        expect(deviceId2, deviceId);
      },
    );
  });
}
