import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/player/data/playback_device_profile.dart';
import 'package:embyplayer/src/features/player/data/playback_settings_store.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:embyplayer/src/features/player/domain/playback_settings.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

class PlaybackService {
  PlaybackService(this._dio, [PlaybackSettingsStore? settingsStore])
    : _settingsStore = settingsStore ?? MemoryPlaybackSettingsStore();

  final Dio _dio;
  final PlaybackSettingsStore _settingsStore;

  Future<PlaybackPlan> createPlan(
    AuthenticatedServer account,
    MediaItem item, {
    Duration? startPosition,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? mediaSourceId,
    PlaybackBitrate? maxStreamingBitrate,
  }) async {
    final resumeAt = startPosition ?? item.resumePosition;
    final settings = await _readSettings();
    final selectedBitrate = maxStreamingBitrate ?? settings.maxStreamingBitrate;
    final uri = _appendPath(
      account.server.apiBaseUri,
      'Items/${item.id}/PlaybackInfo',
    );
    final data = await _requestPlaybackInfo(
      account: account,
      uri: uri,
      startPosition: resumeAt,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      mediaSourceId: mediaSourceId,
      maxStreamingBitrate: selectedBitrate.bitsPerSecond,
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
    final source = _selectSource(sources, preferredId: mediaSourceId);
    final transcodingReasons = <String>{
      ..._readStringList(data['TranscodingReasons']),
      ..._readStringList(source['TranscodingReasons']),
    }.toList(growable: false);
    return _buildPlan(
      account: account,
      item: item,
      source: source,
      playSessionId: playSessionId,
      startPosition: resumeAt,
      requestedAudioStreamIndex: audioStreamIndex,
      requestedSubtitleStreamIndex: subtitleStreamIndex,
      transcodingReasons: transcodingReasons,
    );
  }

  Future<Map<String, dynamic>> _requestPlaybackInfo({
    required AuthenticatedServer account,
    required Uri uri,
    required Duration startPosition,
    required int? audioStreamIndex,
    required int? subtitleStreamIndex,
    required String? mediaSourceId,
    required int maxStreamingBitrate,
  }) async {
    DioException? primaryError;
    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        uri,
        data: {
          'UserId': account.userId,
          'StartTimeTicks': _ticks(startPosition),
          'AudioStreamIndex': ?audioStreamIndex,
          'SubtitleStreamIndex': ?subtitleStreamIndex,
          'MediaSourceId': ?mediaSourceId,
          'MaxStreamingBitrate': maxStreamingBitrate,
          'EnableDirectPlay': true,
          'EnableDirectStream': true,
          'EnableTranscoding': true,
          'AllowVideoStreamCopy': true,
          'AllowAudioStreamCopy': true,
          'IsPlayback': true,
          'AutoOpenLiveStream': true,
          'DeviceProfile': PlaybackDeviceProfile.build(
            maxStreamingBitrate: maxStreamingBitrate,
          ),
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
        if (audioStreamIndex != null) 'AudioStreamIndex': '$audioStreamIndex',
        if (subtitleStreamIndex != null)
          'SubtitleStreamIndex': '$subtitleStreamIndex',
        'MediaSourceId': ?mediaSourceId,
        'MaxStreamingBitrate': '$maxStreamingBitrate',
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

  Future<PlaybackSettings> _readSettings() async {
    try {
      return await _settingsStore.read();
    } on Object {
      return const PlaybackSettings();
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
    return _report(
      account,
      'Sessions/Playing/Stopped',
      snapshot,
      eventName: 'Stopped',
    );
  }

  Future<void> markPlayed(AuthenticatedServer account, String itemId) async {
    try {
      await _dio.postUri<void>(
        _appendPath(
          account.server.apiBaseUri,
          'Users/${account.userId}/PlayedItems/$itemId',
        ),
        options: Options(headers: _serverHeaders(account)),
      );
    } on DioException catch (error) {
      throw _mapDioException(error, fallback: '无法标记为已播放。');
    }
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
      'AudioStreamIndex': snapshot.audioStreamIndex ?? plan.audioStreamIndex,
      'SubtitleStreamIndex': snapshot.subtitlesDisabled
          ? null
          : snapshot.subtitleStreamIndex ?? plan.subtitleStreamIndex,
      'IsPaused': snapshot.isPaused,
      'IsMuted': snapshot.volume <= 0,
      'PositionTicks': _ticks(snapshot.position),
      'VolumeLevel': snapshot.volume.round().clamp(0, 100),
      'PlayMethod': _playMethodName(plan.method),
      'PlaySessionId': plan.playSessionId,
      'PlaybackRate': snapshot.playbackRate,
      'SubtitleOffset': snapshot.subtitleOffset.inMilliseconds,
    };
    if (eventName != null) body['EventName'] = eventName;
    try {
      final uri = _appendPath(account.server.apiBaseUri, path).replace(
        queryParameters: eventName != null ? {'EventName': eventName} : null,
      );
      await _dio.postUri<void>(
        uri,
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

  Map<String, dynamic> _selectSource(
    List<Map<String, dynamic>> sources, {
    String? preferredId,
  }) {
    if (preferredId != null) {
      for (final source in sources) {
        if (_readString(source, 'Id') == preferredId &&
            _sourceIsPlayable(source)) {
          return source;
        }
      }
    }
    for (final source in sources) {
      if (_externalUri(source) != null) return source;
    }
    for (final source in sources) {
      if (source['SupportsDirectPlay'] == true) return source;
    }
    for (final source in sources) {
      if (source['SupportsDirectStream'] == true &&
          _readString(source, 'DirectStreamUrl').isNotEmpty) {
        return source;
      }
    }
    for (final source in sources) {
      if (_readString(source, 'TranscodingUrl').isNotEmpty) return source;
    }
    throw const PlaybackServiceException('当前媒体源无法直放、直传或转码。');
  }

  bool _sourceIsPlayable(Map<String, dynamic> source) {
    return _externalUri(source) != null ||
        source['SupportsDirectPlay'] == true ||
        (source['SupportsDirectStream'] == true &&
            _readString(source, 'DirectStreamUrl').isNotEmpty) ||
        _readString(source, 'TranscodingUrl').isNotEmpty;
  }

  PlaybackPlan _buildPlan({
    required AuthenticatedServer account,
    required MediaItem item,
    required Map<String, dynamic> source,
    required String playSessionId,
    required Duration startPosition,
    required int? requestedAudioStreamIndex,
    required int? requestedSubtitleStreamIndex,
    required List<String> transcodingReasons,
  }) {
    final mediaSourceId = _readString(source, 'Id', fallback: item.id);
    final requiredHeaders = _readHeaders(source['RequiredHttpHeaders']);
    final duration = _durationFromTicks(source['RunTimeTicks']) ?? item.runTime;
    final tracks = _readTracks(source['MediaStreams'], account);
    final audioTracks = tracks
        .where((track) => track.kind == PlaybackTrackKind.audio)
        .toList(growable: false);
    final subtitleTracks = tracks
        .where((track) => track.kind == PlaybackTrackKind.subtitle)
        .toList(growable: false);
    final sourceChapters = _readChapters(source['Chapters']);
    final chapters = sourceChapters.isEmpty ? item.chapters : sourceChapters;
    final selectedAudioStreamIndex =
        requestedAudioStreamIndex ??
        _readInt(source['DefaultAudioStreamIndex']);
    final rawSubtitleStreamIndex =
        requestedSubtitleStreamIndex ??
        _readInt(source['DefaultSubtitleStreamIndex']);
    final selectedSubtitleStreamIndex = rawSubtitleStreamIndex == -1
        ? null
        : rawSubtitleStreamIndex;
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
        duration: duration,
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks,
        chapters: chapters,
        audioStreamIndex: selectedAudioStreamIndex,
        subtitleStreamIndex: selectedSubtitleStreamIndex,
        transcodingReasons: transcodingReasons,
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
        duration: duration,
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks,
        chapters: chapters,
        audioStreamIndex: selectedAudioStreamIndex,
        subtitleStreamIndex: selectedSubtitleStreamIndex,
        transcodingReasons: transcodingReasons,
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
        duration: duration,
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks,
        chapters: chapters,
        audioStreamIndex: selectedAudioStreamIndex,
        subtitleStreamIndex: selectedSubtitleStreamIndex,
        transcodingReasons: transcodingReasons,
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
        duration: duration,
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks,
        chapters: chapters,
        audioStreamIndex: selectedAudioStreamIndex,
        subtitleStreamIndex: selectedSubtitleStreamIndex,
        transcodingReasons: transcodingReasons,
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
    required Duration? duration,
    required List<PlaybackTrackInfo> audioTracks,
    required List<PlaybackTrackInfo> subtitleTracks,
    required List<MediaChapter> chapters,
    required int? audioStreamIndex,
    required int? subtitleStreamIndex,
    required List<String> transcodingReasons,
  }) {
    return PlaybackPlan(
      itemId: item.id,
      mediaSourceId: mediaSourceId,
      playSessionId: playSessionId,
      streamUri: _authenticateUri(account, streamUri),
      method: method,
      httpHeaders: {..._serverHeaders(account), ...requiredHeaders},
      startPosition: startPosition,
      duration: duration,
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      chapters: chapters,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      transcodingReasons: transcodingReasons,
    );
  }

  List<String> _readStringList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Object>()
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  List<MediaChapter> _readChapters(Object? value) {
    if (value is! List) return const [];
    final chapters =
        value
            .whereType<Map>()
            .map((chapter) {
              final ticks = _readInt(chapter['StartPositionTicks']);
              if (ticks == null || ticks < 0) return null;
              final rawName = chapter['Name'];
              final name = rawName is String ? rawName.trim() : '';
              return MediaChapter(
                name: name.isEmpty ? '章节' : name,
                startPosition: Duration(microseconds: ticks ~/ 10),
              );
            })
            .whereType<MediaChapter>()
            .toList(growable: true)
          ..sort((a, b) => a.startPosition.compareTo(b.startPosition));
    return List.unmodifiable(chapters);
  }

  List<PlaybackTrackInfo> _readTracks(
    Object? value,
    AuthenticatedServer account,
  ) {
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map((stream) {
          final type = _readString(stream, 'Type').toLowerCase();
          final kind = switch (type) {
            'audio' => PlaybackTrackKind.audio,
            'subtitle' => PlaybackTrackKind.subtitle,
            _ => null,
          };
          final index = _readInt(stream['Index']);
          if (kind == null || index == null) return null;
          final title = _nullableString(stream, 'Title');
          final language = _nullableString(stream, 'Language');
          final codec = _nullableString(stream, 'Codec');
          final displayTitle =
              _nullableString(stream, 'DisplayTitle') ??
              title ??
              language ??
              '${kind == PlaybackTrackKind.audio ? '音轨' : '字幕'} ${index + 1}';
          final deliveryUrl = _nullableString(stream, 'DeliveryUrl');
          return PlaybackTrackInfo(
            index: index,
            kind: kind,
            label: displayTitle,
            title: title,
            language: language,
            codec: codec,
            channels:
                _nullableString(stream, 'ChannelLayout') ??
                _nullableString(stream, 'Channels'),
            isDefault: stream['IsDefault'] == true,
            isForced: stream['IsForced'] == true,
            isExternal: stream['IsExternal'] == true,
            isText: stream['IsTextSubtitleStream'] == true,
            deliveryUri: deliveryUrl == null
                ? null
                : _authenticatedDeliveryUri(account, deliveryUrl),
          );
        })
        .whereType<PlaybackTrackInfo>()
        .toList(growable: false);
  }

  Uri _authenticatedDeliveryUri(AuthenticatedServer account, String value) {
    return _authenticateUri(
      account,
      _resolveServerUri(account.server.apiBaseUri, value),
    );
  }

  Uri _authenticateUri(AuthenticatedServer account, Uri uri) {
    final base = account.server.apiBaseUri;
    final sameServer =
        uri.scheme == base.scheme &&
        uri.host == base.host &&
        uri.port == base.port;
    if (!sameServer) {
      return uri;
    }
    final token = account.accessToken.trim();
    if (token.isEmpty) {
      return uri;
    }
    final params = Map<String, String>.from(uri.queryParameters);
    params.putIfAbsent('api_key', () => token);
    params.putIfAbsent('X-Emby-Token', () => token);
    params.putIfAbsent('X-MediaBrowser-Token', () => token);
    params.putIfAbsent('token', () => token);
    return uri.replace(queryParameters: params);
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
    final baseSegments = base.pathSegments.where((s) => s.isNotEmpty).toList();
    final valueSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
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
    final baseSegments = base.pathSegments.where((s) => s.isNotEmpty);
    final additionalSegments = path.split('/').where((s) => s.isNotEmpty);
    return base.replace(
      pathSegments: [...baseSegments, ...additionalSegments],
    );
  }

  Map<String, String> _serverHeaders(AuthenticatedServer account) {
    final token = account.accessToken;
    final deviceId = account.deviceId;
    final scheme = account.server.kind == ServerKind.emby ? 'Emby' : 'MediaBrowser';
    final authValue = deviceId.isNotEmpty
        ? '$scheme Client="PEeK", Device="Windows", DeviceId="$deviceId", Version="0.1.0", Token="$token"'
        : 'MediaBrowser Token="$token"';
    return {
      'Authorization': authValue,
      'X-Emby-Token': token,
      'X-MediaBrowser-Token': token,
    };
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

  String? _nullableString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  Duration? _durationFromTicks(Object? value) {
    final ticks = _readInt(value);
    return ticks == null ? null : Duration(microseconds: ticks ~/ 10);
  }

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
}

class PlaybackServiceException implements Exception {
  const PlaybackServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
