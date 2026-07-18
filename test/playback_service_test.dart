import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/player/data/playback_service.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final account = _account(Uri.parse('http://192.168.1.20:8096'));
  const item = MediaItem(
    id: 'item-id',
    name: '示例电影',
    kind: MediaItemKind.movie,
    resumePosition: Duration(minutes: 12),
  );

  test('creates direct STRM plan with required remote headers', () async {
    RequestOptions? request;
    final service = PlaybackService(
      _dioWithJsonResponse({
        'PlaySessionId': 'session-id',
        'MediaSources': [
          {
            'Id': 'source-id',
            'Protocol': 'Http',
            'Path': 'https://media.example.test/live/master.m3u8',
            'IsRemote': true,
            'SupportsDirectPlay': true,
            'RunTimeTicks': 72000000000,
            'RequiredHttpHeaders': {
              'Referer': 'https://media.example.test/',
              'User-Agent': 'Projection Booth',
            },
            'DefaultAudioStreamIndex': 1,
            'DefaultSubtitleStreamIndex': 2,
            'MediaStreams': [
              {
                'Index': 1,
                'Type': 'Audio',
                'DisplayTitle': '中文 AAC 5.1',
                'Language': 'chi',
                'Codec': 'aac',
                'ChannelLayout': '5.1',
                'IsDefault': true,
              },
              {
                'Index': 2,
                'Type': 'Subtitle',
                'DisplayTitle': '简体中文 SRT',
                'Language': 'chi',
                'Codec': 'srt',
                'IsExternal': true,
                'IsTextSubtitleStream': true,
                'DeliveryUrl': '/Videos/item-id/Subtitles/2/Stream.srt',
              },
            ],
          },
        ],
      }, onRequest: (options) => request = options),
    );

    final plan = await service.createPlan(account, item);

    expect(request?.uri.path, '/Items/item-id/PlaybackInfo');
    expect(request?.data, isA<Map<String, dynamic>>());
    expect(plan.method, PlaybackMethod.directPlay);
    expect(
      plan.streamUri,
      Uri.parse('https://media.example.test/live/master.m3u8'),
    );
    expect(plan.httpHeaders['Referer'], 'https://media.example.test/');
    expect(plan.httpHeaders.containsKey('X-Emby-Token'), isFalse);
    expect(plan.startPosition, const Duration(minutes: 12));
    expect(plan.duration, const Duration(hours: 2));
    expect(plan.audioStreamIndex, 1);
    expect(plan.subtitleStreamIndex, 2);
    expect(plan.audioTracks.single.label, '中文 AAC 5.1');
    expect(plan.audioTracks.single.channels, '5.1');
    expect(plan.subtitleTracks.single.isExternal, isTrue);
    expect(
      plan.subtitleTracks.single.deliveryUri?.path,
      '/Videos/item-id/Subtitles/2/Stream.srt',
    );
    expect(
      plan.subtitleTracks.single.deliveryUri?.queryParameters['api_key'],
      'secret-token',
    );
  });

  test('requests selected server tracks when rebuilding a plan', () async {
    RequestOptions? request;
    final service = PlaybackService(
      _dioWithJsonResponse({
        'PlaySessionId': 'track-session',
        'MediaSources': [
          {
            'Id': 'source-id',
            'Protocol': 'File',
            'Container': 'mkv',
            'SupportsDirectPlay': true,
            'DefaultAudioStreamIndex': 1,
            'DefaultSubtitleStreamIndex': 2,
          },
        ],
      }, onRequest: (options) => request = options),
    );

    final plan = await service.createPlan(
      account,
      item,
      startPosition: const Duration(minutes: 20),
      audioStreamIndex: 3,
      subtitleStreamIndex: -1,
      mediaSourceId: 'source-id',
    );

    final body = request?.data as Map<String, dynamic>;
    expect(body['AudioStreamIndex'], 3);
    expect(body['SubtitleStreamIndex'], -1);
    expect(body['MediaSourceId'], 'source-id');
    expect(body['StartTimeTicks'], 12000000000);
    expect(plan.audioStreamIndex, 3);
    expect(plan.subtitleStreamIndex, isNull);
  });

  test('skips direct stream sources without a stream url', () async {
    final service = PlaybackService(
      _dioWithJsonResponse({
        'PlaySessionId': 'session-id',
        'MediaSources': [
          {
            'Id': 'broken-source',
            'Protocol': 'File',
            'SupportsDirectStream': true,
          },
          {
            'Id': 'working-source',
            'Protocol': 'File',
            'Container': 'mkv',
            'SupportsDirectPlay': true,
          },
        ],
      }),
    );

    final plan = await service.createPlan(account, item);

    expect(plan.mediaSourceId, 'working-source');
    expect(plan.method, PlaybackMethod.directPlay);
  });

  test('creates authenticated server stream for a local file', () async {
    final service = PlaybackService(
      _dioWithJsonResponse({
        'PlaySessionId': 'session-id',
        'MediaSources': [
          {
            'Id': 'source-id',
            'Protocol': 'File',
            'Path': r'D:\Media\movie.mkv',
            'Container': 'mkv',
            'SupportsDirectPlay': true,
          },
        ],
      }),
    );

    final plan = await service.createPlan(account, item);

    expect(plan.method, PlaybackMethod.directPlay);
    expect(plan.streamUri.path, '/Videos/item-id/stream.mkv');
    expect(plan.streamUri.queryParameters['Static'], 'true');
    expect(plan.streamUri.queryParameters['MediaSourceId'], 'source-id');
    expect(plan.httpHeaders['X-Emby-Token'], 'secret-token');
  });

  test('keeps reverse proxy base path for direct stream urls', () async {
    final proxyAccount = _account(Uri.parse('https://media.example.test/emby'));
    final service = PlaybackService(
      _dioWithJsonResponse({
        'PlaySessionId': 'session-id',
        'MediaSources': [
          {
            'Id': 'source-id',
            'Protocol': 'File',
            'SupportsDirectStream': true,
            'DirectStreamUrl': '/Videos/item-id/stream.mkv?Static=false',
          },
        ],
      }),
    );

    final plan = await service.createPlan(proxyAccount, item);

    expect(plan.method, PlaybackMethod.directStream);
    expect(plan.streamUri.path, '/emby/Videos/item-id/stream.mkv');
    expect(plan.streamUri.queryParameters['Static'], 'false');
  });

  test(
    'falls back to legacy GET playback info when POST is rejected',
    () async {
      final methods = <String>[];
      RequestOptions? fallbackRequest;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              methods.add(options.method);
              if (options.method == 'POST') {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response<Map<String, dynamic>>(
                      requestOptions: options,
                      statusCode: 400,
                      data: const {'Message': 'Unsupported device profile'},
                    ),
                  ),
                );
                return;
              }
              fallbackRequest = options;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {
                    'PlaySessionId': 'fallback-session',
                    'MediaSources': [
                      {
                        'Id': 'strm-source',
                        'Protocol': 'Http',
                        'Path': 'https://media.example.test/fallback.m3u8',
                        'SupportsDirectPlay': true,
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );

      final plan = await PlaybackService(dio).createPlan(account, item);

      expect(methods, ['POST', 'GET']);
      expect(fallbackRequest?.uri.queryParameters['UserId'], 'user-id');
      expect(plan.playSessionId, 'fallback-session');
      expect(plan.streamUri.path, '/fallback.m3u8');
    },
  );

  test('explains playback info timeouts for STRM sources', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.receiveTimeout,
              ),
            );
          },
        ),
      );

    await expectLater(
      PlaybackService(dio).createPlan(account, item),
      throwsA(
        isA<PlaybackServiceException>().having(
          (error) => error.message,
          'message',
          contains('服务器能够访问 STRM'),
        ),
      ),
    );
  });

  test('reports playback progress using server ticks', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<void>(requestOptions: options, statusCode: 204),
            );
          },
        ),
      );
    final plan = PlaybackPlan(
      itemId: 'item-id',
      mediaSourceId: 'source-id',
      playSessionId: 'session-id',
      streamUri: Uri.parse('https://media.example.test/video.mkv'),
      method: PlaybackMethod.directPlay,
    );

    await PlaybackService(dio).reportProgress(
      account,
      PlaybackSessionSnapshot(
        plan: plan,
        position: const Duration(seconds: 42),
        isPaused: false,
        volume: 80,
        audioStreamIndex: 4,
        subtitlesDisabled: true,
        playbackRate: 1.5,
      ),
    );

    expect(request?.uri.path, '/Sessions/Playing/Progress');
    final body = request?.data as Map<String, dynamic>;
    expect(body['PositionTicks'], 420000000);
    expect(body['PlayMethod'], 'DirectPlay');
    expect(body['EventName'], 'TimeUpdate');
    expect(body['AudioStreamIndex'], 4);
    expect(body['SubtitleStreamIndex'], isNull);
    expect(body['PlaybackRate'], 1.5);
  });
}

AuthenticatedServer _account(Uri baseUri) {
  return AuthenticatedServer(
    server: DiscoveredServer(
      kind: ServerKind.jellyfin,
      name: 'Living Room',
      version: '10.11.6',
      serverId: 'server-id',
      apiBaseUri: baseUri,
    ),
    userId: 'user-id',
    userName: 'Alex',
    deviceId: 'device-id',
    accessToken: 'secret-token',
  );
}

Dio _dioWithJsonResponse(
  Map<String, dynamic> data, {
  void Function(RequestOptions)? onRequest,
}) {
  return Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          onRequest?.call(options);
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: data,
            ),
          );
        },
      ),
    );
}
