import 'dart:async';

import 'package:dio/dio.dart';

class SessionExpiryCoordinator {
  final _events = StreamController<SessionExpiryEvent>.broadcast(sync: true);
  String? _pendingToken;

  Stream<SessionExpiryEvent> get events => _events.stream;

  void notify(String accessToken) {
    if (accessToken.isEmpty || _pendingToken != null || _events.isClosed) {
      return;
    }
    _pendingToken = accessToken;
    _events.add(SessionExpiryEvent._(accessToken));
  }

  void acknowledge(SessionExpiryEvent event) {
    if (_pendingToken == event._accessToken) _pendingToken = null;
  }

  Future<void> dispose() => _events.close();
}

class SessionExpiryEvent {
  const SessionExpiryEvent._(this._accessToken);

  final String _accessToken;

  bool matches(String accessToken) {
    return accessToken == _accessToken;
  }
}

class SessionExpiryInterceptor extends Interceptor {
  SessionExpiryInterceptor(this._coordinator);

  final SessionExpiryCoordinator _coordinator;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    final accessToken = _accessToken(err.requestOptions);
    if ((status == 401 || status == 403) && accessToken != null) {
      _coordinator.notify(accessToken);
    }
    handler.next(err);
  }

  String? _accessToken(RequestOptions request) {
    for (final entry in request.headers.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'x-emby-token' || key == 'x-mediabrowser-token') {
        final value = entry.value?.toString() ?? '';
        if (value.isNotEmpty) return value;
      }
      if (key == 'authorization') {
        final value = entry.value?.toString() ?? '';
        final match = RegExp(r'Token="([^"]+)"').firstMatch(value);
        if (match != null && match.group(1) != null && match.group(1)!.isNotEmpty) {
          return match.group(1);
        }
      }
    }
    return null;
  }
}
