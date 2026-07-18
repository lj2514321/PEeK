import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

class PlaybackService {
  PlaybackService(this._dio);

  final Dio _dio;

  Future<PlaybackPlan> createPlan(
    AuthenticatedServer account,
    MediaItem item, {
    Duration? startPosition,
  }) async {
    final resumeAt = startPosition ?? item.resumePosition;
    final uri = _appendPath(
      account.server.apiBaseUri,
      'Items/${item.id}/PlaybackInfo',
    );
    final data = await _requestPlaybackInfo(
      account: account,
      uri: uri,
      startPosition: resumeAt,
    );
    final rawSources = data['MediaSources'];
    final playSessionId = _readString(data, 'PlaySessionId');
    if (rawSources is! List || rawSources.isEmpty) {
      final errorCode = _readString(data, 'ErrorCode');
      throw PlaybackServiceException(
        errorCode.isEmpty ? '服务器没有返回可播放的媒体源。' : '服务器无法播放此项目：$errorCode',
      );
    }

    final sources = rawSources.whereType<Map<String, dynamic>>().toList();
    if (sources.isEmpty) {
      throw const PlaybackServiceException('服务器没有返回可播放的媒体源。');
    }
    final source = _selectSource(sources);
    return _buildPlan(
      account: account,
      item: item,
      source: source,
      playSessionId: playSessionId,
      startPosition: resumeAt,
    );
  }

  Future<Map<String, dynamic>> _requestPlaybackInfo({
    required AuthenticatedServer account,
    required Uri uri,
    required Duration startPosition,
  }) async {
    DioException? primaryError;
    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        uri,
        data: {
          'UserId': account.userId,
          'StartTimeTicks': _ticks(startPosition),
          'MaxStreamingBitrate': 160000000,
          'EnableDirectPlay': true,
          'EnableDirectStream': true,
          'EnableTranscoding': true,
          'AllowVideoStreamCopy': true,
          'AllowAudioStreamCopy': true,
          'IsPlayback': true,
          'AutoOpenLiveStream': true,
          'DeviceProfile': _deviceProfile,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          headers: _serverHeaders(account),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      if (response.data != null) return response.data!;
    } on DioException catch (error) {
      primaryError = error;
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw _mapDioException(error, fallback: '无法获取播放信息。');
      }
    }

    final fallbackUri = uri.replace(
      queryParameters: {
        'UserId': account.userId,
        'StartTimeTicks': '${_ticks(startPosition)}',
        'MaxStreamingBitrate': '160000000',
        'IsPlayback': 'true',
        'AutoOpenLiveStream': 'true',
      },
    );
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        fallbackUri,
        options: Options(
          headers: _serverHeaders(account),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      if (response.data != null) return response.data!;
      throw const PlaybackServiceException('服务器返回了空的播放信息。');
    } on PlaybackServiceException {
      rethrow;
    } on DioException catch (fallbackError) {
      throw _playbackInfoException(fallbackError, primaryError: primaryError);
    }
  }

  Future<void> reportStarted(
    AuthenticatedServer account,
    PlaybackSessionSnapshot snapshot,
  ) {
    return _report(account, 'Sessions/Playing', snapshot);
  }

  Future<void> reportProgress(
    AuthenticatedServer account,
    PlaybackSessionSnapshot snapshot, {
    String eventName = 'TimeUpdate',
  }) {
    return _report(
      account,
      'Sessions/Playing/Progress',
      snapshot,
      eventName: eventName,
    );
  }

  Future<void> reportStopped(
    AuthenticatedServer account,
    PlaybackSessionSnapshot snapshot,
  ) {
    return _report(account, 'Sessions/Playing/Stopped', snapshot);
  }

  Future<void> _report(
    AuthenticatedServer account,
    String path,
    PlaybackSessionSnapshot snapshot, {
    String? eventName,
  }) async {
    final plan = snapshot.plan;
    final body = <String, dynamic>{
      'QueueableMediaTypes': ['Video', 'Audio'],
      'CanSeek': true,
      'ItemId': plan.itemId,
      'MediaSourceId': plan.mediaSourceId,
      'AudioStreamIndex': plan.audioStreamIndex,
      'SubtitleStreamIndex': plan.subtitleStreamIndex,
      'IsPaused': snapshot.isPaused,
      'IsMuted': snapshot.volume <= 0,
      'PositionTicks': _ticks(snapshot.position),
      'VolumeLevel': snapshot.volume.round().clamp(0, 100),
      'PlayMethod': _playMethodName(plan.method),
      'PlaySessionId': plan.playSessionId,
      'PlaybackRate': 1.0,
    };
    if (eventName != null) body['EventName'] = eventName;
    try {
      await _dio.postUri<void>(
        _appendPath(account.server.apiBaseUri, path),
        data: body,
        options: Options(
          contentType: Headers.jsonContentType,
          headers: _serverHeaders(account),
        ),
      );
    } on DioException catch (error) {
      throw _mapDioException(error, fallback: '无法同步播放进度。');
    }
  }

  Map<String, dynamic> _selectSource(List<Map<String, dynamic>> sources) {
    for (final source in sources) {
      if (_externalUri(source) != null) return source;
    }
    for (final source in sources) {
      if (source['SupportsDirectPlay'] == true) return source;
    }
    for (final source in sources) {
      if (source['SupportsDirectStream'] == true) return source;
    }
    for (final source in sources) {
      if (_readString(source, 'TranscodingUrl').isNotEmpty) return source;
    }
    throw const PlaybackServiceException('当前媒体源无法直放、直传或转码。');
  }

  PlaybackPlan _buildPlan({
    required AuthenticatedServer account,
    required MediaItem item,
    required Map<String, dynamic> source,
    required String playSessionId,
    required Duration startPosition,
  }) {
    final mediaSourceId = _readString(source, 'Id', fallback: item.id);
    final requiredHeaders = _readHeaders(source['RequiredHttpHeaders']);
    final external = _externalUri(source);
    if (external != null) {
      return PlaybackPlan(
        itemId: item.id,
        mediaSourceId: mediaSourceId,
        playSessionId: playSessionId,
        streamUri: external,
        method: PlaybackMethod.directPlay,
        httpHeaders: requiredHeaders,
        startPosition: startPosition,
        audioStreamIndex: _readInt(source['DefaultAudioStreamIndex']),
        subtitleStreamIndex: _readInt(source['DefaultSubtitleStreamIndex']),
      );
    }

    final directStreamUrl = _readString(source, 'DirectStreamUrl');
    if (source['SupportsDirectStream'] == true && directStreamUrl.isNotEmpty) {
      return _serverPlan(
        account: account,
        item: item,
        source: source,
        mediaSourceId: mediaSourceId,
        playSessionId: playSessionId,
        streamUri: _resolveServerUri(
          account.server.apiBaseUri,
          directStreamUrl,
        ),
        method: PlaybackMethod.directStream,
        requiredHeaders: requiredHeaders,
        startPosition: startPosition,
      );
    }

    if (source['SupportsDirectPlay'] == true) {
      final container = _readString(source, 'Container').split(',').first;
      final streamName = container.isEmpty ? 'stream' : 'stream.$container';
      final streamUri =
          _appendPath(
            account.server.apiBaseUri,
            'Videos/${item.id}/$streamName',
          ).replace(
            queryParameters: {
              'Static': 'true',
              'MediaSourceId': mediaSourceId,
              'DeviceId': account.deviceId,
              if (playSessionId.isNotEmpty) 'PlaySessionId': playSessionId,
            },
          );
      return _serverPlan(
        account: account,
        item: item,
        source: source,
        mediaSourceId: mediaSourceId,
        playSessionId: playSessionId,
        streamUri: streamUri,
        method: PlaybackMethod.directPlay,
        requiredHeaders: requiredHeaders,
        startPosition: startPosition,
      );
    }

    final transcodingUrl = _readString(source, 'TranscodingUrl');
    if (transcodingUrl.isNotEmpty) {
      return _serverPlan(
        account: account,
        item: item,
        source: source,
        mediaSourceId: mediaSourceId,
        playSessionId: playSessionId,
        streamUri: _resolveServerUri(account.server.apiBaseUri, transcodingUrl),
        method: PlaybackMethod.transcode,
        requiredHeaders: requiredHeaders,
        startPosition: startPosition,
      );
    }

    throw const PlaybackServiceException('服务器没有提供可用的播放地址。');
  }

  PlaybackPlan _serverPlan({
    required AuthenticatedServer account,
    required MediaItem item,
    required Map<String, dynamic> source,
    required String mediaSourceId,
    required String playSessionId,
    required Uri streamUri,
    required PlaybackMethod method,
    required Map<String, String> requiredHeaders,
    required Duration startPosition,
  }) {
    return PlaybackPlan(
      itemId: item.id,
      mediaSourceId: mediaSourceId,
      playSessionId: playSessionId,
      streamUri: streamUri,
      method: method,
      httpHeaders: {..._serverHeaders(account), ...requiredHeaders},
      startPosition: startPosition,
      audioStreamIndex: _readInt(source['DefaultAudioStreamIndex']),
      subtitleStreamIndex: _readInt(source['DefaultSubtitleStreamIndex']),
    );
  }

  Uri? _externalUri(Map<String, dynamic> source) {
    final protocol = _readString(source, 'Protocol').toLowerCase();
    final path = _readString(source, 'Path');
    final uri = Uri.tryParse(path);
    if ((protocol == 'http' || protocol == 'https') &&
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri;
    }
    return null;
  }

  Uri _resolveServerUri(Uri base, String value) {
    final uri = Uri.parse(value);
    if (uri.hasScheme) return uri;
    final baseSegments = base.pathSegments;
    final valueSegments = uri.pathSegments;
    final alreadyPrefixed =
        baseSegments.isNotEmpty &&
        valueSegments.length >= baseSegments.length &&
        _startsWith(valueSegments, baseSegments);
    return base.replace(
      pathSegments: alreadyPrefixed
          ? valueSegments
          : [...baseSegments, ...valueSegments],
      query: uri.hasQuery ? uri.query : null,
      fragment: null,
    );
  }

  bool _startsWith(List<String> value, List<String> prefix) {
    for (var index = 0; index < prefix.length; index++) {
      if (value[index] != prefix[index]) return false;
    }
    return true;
  }

  Uri _appendPath(Uri base, String path) {
    return base.replace(
      pathSegments: [...base.pathSegments, ...path.split('/')],
    );
  }

  Map<String, String> _serverHeaders(AuthenticatedServer account) {
    return {'X-Emby-Token': account.accessToken};
  }

  Map<String, String> _readHeaders(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value != null)
          entry.key as String: entry.value.toString(),
    };
  }

  String _readString(
    Map<String, dynamic>? data,
    String key, {
    String fallback = '',
  }) {
    final value = data?[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  int? _readInt(Object? value) => value is num ? value.toInt() : null;

  int _ticks(Duration value) => value.inMicroseconds * 10;

  String _playMethodName(PlaybackMethod method) {
    return switch (method) {
      PlaybackMethod.directPlay => 'DirectPlay',
      PlaybackMethod.directStream => 'DirectStream',
      PlaybackMethod.transcode => 'Transcode',
    };
  }

  PlaybackServiceException _mapDioException(
    DioException error, {
    required String fallback,
  }) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return const PlaybackServiceException('登录凭据已失效，请重新登录服务器。');
    }
    return PlaybackServiceException(
      status == null ? fallback : '$fallback（HTTP $status）',
    );
  }

  PlaybackServiceException _playbackInfoException(
    DioException error, {
    DioException? primaryError,
  }) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return const PlaybackServiceException('登录凭据已失效，请重新登录服务器。');
    }
    if (_isTimeout(error) ||
        (primaryError != null && _isTimeout(primaryError))) {
      return const PlaybackServiceException(
        '获取播放信息超时。请确认 Jellyfin/Emby 服务器能够访问 STRM 文件中的源地址。',
      );
    }
    final detail = _responseDetail(error.response?.data);
    if (status != null) {
      return PlaybackServiceException(
        detail == null
            ? '无法获取播放信息（HTTP $status）。'
            : '无法获取播放信息（HTTP $status：$detail）。',
      );
    }
    final reason = error.error?.toString();
    return PlaybackServiceException(
      reason == null || reason.isEmpty
          ? '无法连接服务器获取播放信息。'
          : '无法连接服务器获取播放信息：$reason',
    );
  }

  bool _isTimeout(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }

  String? _responseDetail(Object? value) {
    if (value is Map) {
      final message =
          value['Message'] ?? value['message'] ?? value['ErrorCode'];
      return message?.toString();
    }
    if (value is String && value.isNotEmpty && value.length <= 180) {
      return value;
    }
    return null;
  }

  static const _deviceProfile = <String, dynamic>{
    'Name': 'PEeK Windows',
    'SupportedMediaTypes': 'Video,Audio',
    'MaxStreamingBitrate': 160000000,
    'MusicStreamingTranscodingBitrate': 320000,
    'DirectPlayProfiles': [
      {
        'Container':
            'mkv,mp4,m4v,mov,avi,ts,m2ts,mpeg,mpg,webm,wmv,flv,vob,ogv,3gp',
        'Type': 'Video',
      },
      {'Container': 'mp3,aac,m4a,flac,ogg,opus,wav,wma', 'Type': 'Audio'},
    ],
    'TranscodingProfiles': [
      {
        'Container': 'ts',
        'Type': 'Video',
        'VideoCodec': 'h264,hevc',
        'AudioCodec': 'aac,ac3,eac3,mp3,opus',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'MinSegments': 1,
        'BreakOnNonKeyFrames': true,
      },
    ],
    'SubtitleProfiles': [
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'Embed'},
      {'Format': 'ssa', 'Method': 'Embed'},
      {'Format': 'pgssub', 'Method': 'Embed'},
      {'Format': 'dvdsub', 'Method': 'Embed'},
    ],
  };
}

class PlaybackServiceException implements Exception {
  const PlaybackServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
