import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/servers/data/server_discovery_service.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('discovery appends API paths as separate URI segments', () async {
    final requestedUris = <Uri>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestedUris.add(options.uri);
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'ServerName': 'Living Room',
                  'Version': '10.11.6',
                  'ProductName': 'Jellyfin Server',
                  'Id': 'server-id',
                },
              ),
            );
          },
        ),
      );

    final server = await ServerDiscoveryService(
      dio,
    ).discover('http://192.168.110.110:8096/');

    expect(requestedUris, [
      Uri.parse('http://192.168.110.110:8096/System/Info/Public'),
    ]);
    expect(server.kind, ServerKind.jellyfin);
    expect(server.name, 'Living Room');
  });
}
