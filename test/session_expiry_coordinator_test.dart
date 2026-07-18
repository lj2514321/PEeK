import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/network/session_expiry_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emits one event for repeated authenticated 401 responses', () async {
    final coordinator = SessionExpiryCoordinator();
    final events = <SessionExpiryEvent>[];
    final subscription = coordinator.events.listen(events.add);
    final dio = Dio()..httpClientAdapter = _StatusAdapter(401);
    dio.interceptors.add(SessionExpiryInterceptor(coordinator));

    for (var index = 0; index < 2; index++) {
      await expectLater(
        dio.get<void>(
          'http://server.local/Items',
          options: Options(headers: const {'X-Emby-Token': 'secret'}),
        ),
        throwsA(isA<DioException>()),
      );
    }

    expect(events, hasLength(1));
    expect(events.single.matches('secret'), isTrue);
    expect(events.single.matches('another-token'), isFalse);
    coordinator.acknowledge(events.single);
    await expectLater(
      dio.get<void>(
        'http://server.local/Items',
        options: Options(headers: const {'X-Emby-Token': 'secret'}),
      ),
      throwsA(isA<DioException>()),
    );
    expect(events, hasLength(2));

    await subscription.cancel();
    await coordinator.dispose();
  });

  test('ignores unauthenticated login failures', () async {
    final coordinator = SessionExpiryCoordinator();
    final events = <SessionExpiryEvent>[];
    final subscription = coordinator.events.listen(events.add);
    final dio = Dio()..httpClientAdapter = _StatusAdapter(401);
    dio.interceptors.add(SessionExpiryInterceptor(coordinator));

    await expectLater(
      dio.post<void>(
        'http://server.local/Users/AuthenticateByName',
        options: Options(
          headers: const {'X-Emby-Authorization': 'MediaBrowser Client="PEeK"'},
        ),
      ),
      throwsA(isA<DioException>()),
    );

    expect(events, isEmpty);
    await subscription.cancel();
    await coordinator.dispose();
  });
}

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.statusCode);

  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString('', statusCode);
  }

  @override
  void close({bool force = false}) {}
}
