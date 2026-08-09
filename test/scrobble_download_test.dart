import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/download/data/download_manager_service.dart';
import 'package:embyplayer/src/features/scrobble/data/bangumi_scrobble_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BangumiScrobbleService parses search result correctly', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': [
                    {'id': 12345, 'name': 'Demon Slayer'},
                  ],
                },
              ),
            );
          },
        ),
      );

    final service = BangumiScrobbleService(dio);
    final subjectId = await service.searchSubjectId('Demon Slayer');
    expect(subjectId, 12345);
  });

  test('DownloadTask data model serializes correctly', () {
    const task = DownloadTask(
      id: 'media-1',
      title: 'Sample Video',
      url: 'http://127.0.0.1:8096/stream',
      savePath: '/path/to/media-1.mp4',
      progress: 0.5,
      completed: false,
    );

    expect(task.id, 'media-1');
    expect(task.progress, 0.5);
    expect(task.completed, isFalse);

    final updated = task.copyWith(progress: 1.0, completed: true);
    expect(updated.progress, 1.0);
    expect(updated.completed, isTrue);
  });
}
