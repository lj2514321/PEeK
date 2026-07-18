import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

class ServerDiscoveryService {
  ServerDiscoveryService(this._dio);

  final Dio _dio;

  Future<DiscoveredServer> discover(String rawAddress) async {
    final input = _parseAddress(rawAddress);
    final candidates = <Uri>[
      input,
      if (!_endsWithEmby(input)) _appendPath(input, 'emby'),
    ];

    for (final apiBaseUri in candidates) {
      try {
        final response = await _dio.getUri<Map<String, dynamic>>(
          _appendPath(apiBaseUri, 'System/Info/Public'),
          options: Options(validateStatus: (status) => status == 200),
        );
        final data = response.data;
        if (data == null) continue;

        final productName = _readString(data, 'ProductName');
        final kind = _detectKind(productName);
        if (kind == null) continue;

        return DiscoveredServer(
          kind: kind,
          name: _readString(data, 'ServerName', fallback: kind.label),
          version: _readString(data, 'Version', fallback: '未知版本'),
          serverId: _readString(data, 'Id'),
          apiBaseUri: apiBaseUri,
        );
      } on DioException {
        // Try the next compatible API base path before reporting failure.
      }
    }

    throw const ServerDiscoveryException(
      '没有识别到 Jellyfin 或 Emby 服务。请检查地址、端口和网络连接。',
    );
  }

  Uri _parseAddress(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) {
      throw const ServerDiscoveryException('请输入服务器地址。');
    }
    if (!normalized.contains('://')) normalized = 'http://$normalized';

    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) {
      throw const ServerDiscoveryException('服务器地址格式不正确。');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const ServerDiscoveryException('服务器地址必须使用 HTTP 或 HTTPS。');
    }

    return uri.replace(
      path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
      query: null,
      fragment: null,
    );
  }

  bool _endsWithEmby(Uri uri) {
    return uri.pathSegments.isNotEmpty && uri.pathSegments.last == 'emby';
  }

  Uri _appendPath(Uri base, String path) {
    return base.replace(
      pathSegments: [...base.pathSegments, ...path.split('/')],
    );
  }

  ServerKind? _detectKind(String productName) {
    final normalized = productName.toLowerCase();
    if (normalized.contains('jellyfin')) return ServerKind.jellyfin;
    if (normalized.contains('emby')) return ServerKind.emby;
    return null;
  }

  String _readString(
    Map<String, dynamic> data,
    String key, {
    String fallback = '',
  }) {
    final value = data[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }
}

class ServerDiscoveryException implements Exception {
  const ServerDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}
