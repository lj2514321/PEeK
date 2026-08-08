import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final serverUri = Uri.parse('http://127.0.0.1:8096');

  test('initiateQuickConnect sends POST request and parses code and secret', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'Code': '1234',
                  'Secret': 'secret-xyz',
                },
              ),
            );
          },
        ),
      );

    final service = MediaLibraryService(dio);
    final result = await service.initiateQuickConnect(serverUri);

    expect(request?.method, 'POST');
    expect(request?.uri.path, '/QuickConnect/Initiate');
    expect(result?.code, '1234');
    expect(result?.secret, 'secret-xyz');
  });

  test('checkQuickConnectState checks authorization status', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'Authenticated': true,
                  'AuthenticationResult': {
                    'AccessToken': 'token-quick',
                    'User': {
                      'Id': 'user-quick',
                      'Name': 'QuickUser',
                    },
                  },
                },
              ),
            );
          },
        ),
      );

    final service = MediaLibraryService(dio);
    final state = await service.checkQuickConnectState(serverUri, 'secret-xyz');

    expect(request?.method, 'GET');
    expect(request?.uri.path, '/QuickConnect/Connect');
    expect(request?.uri.queryParameters['secret'], 'secret-xyz');
    expect(state?.authenticated, isTrue);
    expect(state?.accessToken, 'token-quick');
    expect(state?.userId, 'user-quick');
    expect(state?.userName, 'QuickUser');
  });
}
