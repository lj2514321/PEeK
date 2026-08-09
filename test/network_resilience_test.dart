import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/storage/secure_token_store.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/data/server_authentication_service.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  final server = DiscoveredServer(
    kind: ServerKind.emby,
    name: 'Cinema Server',
    version: '4.8.0.0',
    serverId: 'server-1',
    apiBaseUri: Uri.parse('http://127.0.0.1:8096'),
  );

  test('Network Resilience: Handles HTTP 401 Unauthenticated exception smoothly', () async {
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
                  statusMessage: 'Unauthorized token expired',
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

    final service = ServerAuthenticationService(dio, SecureTokenStore());

    expect(
      () => service.login(
        server: server,
        username: 'admin',
        password: 'wrong-password',
      ),
      throwsA(isA<ServerAuthenticationException>()),
    );
  });

  test('Network Resilience: Maps DioException to MediaLibraryException on network timeout', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );

    final service = MediaLibraryService(dio);
    final account = AuthenticatedServer(
      server: server,
      userId: 'user-1',
      userName: 'admin',
      deviceId: 'device-1',
      accessToken: 'token-123',
    );

    expect(
      () => service.getLibraries(account, forceRefresh: true),
      throwsA(isA<MediaLibraryException>()),
    );
  });
}
