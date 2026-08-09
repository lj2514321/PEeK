import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final server = DiscoveredServer(
    kind: ServerKind.emby,
    name: 'Cinema Server',
    version: '4.8.0.0',
    serverId: 'server-1',
    apiBaseUri: Uri.parse('http://127.0.0.1:8096'),
  );
  final account = AuthenticatedServer(
    server: server,
    userId: 'user-1',
    userName: 'admin',
    deviceId: 'device-1',
    accessToken: 'token-123',
  );
  const item = MediaItem(
    id: 'item-h264',
    name: 'Matrix H264 Sample',
    kind: MediaItemKind.movie,
  );

  test('Codec Matrix: Direct Play for supported H.264 streams', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'PlaySessionId': 'session-1',
                  'MediaSources': [
                    {
                      'Id': 'source-h264',
                      'SupportsDirectPlay': true,
                      'Path': 'F:\\Media\\matrix_h264.mp4',
                      'Protocol': 'File',
                      'Container': 'mp4',
                      'VideoCodec': 'h264',
                      'AudioCodec': 'aac',
                      'MediaStreams': [
                        {'Type': 'Video', 'Codec': 'h264', 'Index': 0},
                        {'Type': 'Audio', 'Codec': 'aac', 'Index': 1},
                      ],
                    }
                  ],
                },
              ),
            );
          },
        ),
      );

    final service = PlaybackService(dio);
    final plan = await service.createPlan(account, item);

    expect(plan.method, PlaybackMethod.directPlay);
    expect(plan.mediaSourceId, 'source-h264');
  });

  test('Codec Matrix: Direct Stream for supported container remux (HEVC/MKV)', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'PlaySessionId': 'session-2',
                  'MediaSources': [
                    {
                      'Id': 'source-hevc',
                      'SupportsDirectPlay': false,
                      'SupportsDirectStream': true,
                      'DirectStreamUrl': '/Videos/item-hevc/stream.mkv?static=true',
                      'Protocol': 'Http',
                      'Container': 'mkv',
                      'VideoCodec': 'hevc',
                      'AudioCodec': 'ac3',
                      'MediaStreams': [
                        {'Type': 'Video', 'Codec': 'hevc', 'Index': 0},
                        {'Type': 'Audio', 'Codec': 'ac3', 'Index': 1},
                      ],
                    }
                  ],
                },
              ),
            );
          },
        ),
      );

    final service = PlaybackService(dio);
    final plan = await service.createPlan(account, item);

    expect(plan.method, PlaybackMethod.directStream);
    expect(plan.streamUri.toString(), contains('/Videos/item-hevc/stream.mkv'));
  });
}
