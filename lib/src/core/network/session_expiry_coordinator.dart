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
      if (entry.key.toLowerCase() == 'x-emby-token') {
        final value = entry.value?.toString() ?? '';
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }
}
