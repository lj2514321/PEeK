import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/download/domain/download_task_item.dart';
import 'package:embyplayer/src/features/scrobble/data/bangumi_scrobble_service.dart';
import 'package:embyplayer/src/features/scrobble/domain/bangumi_profile.dart';
import 'package:embyplayer/src/features/scrobble/domain/bangumi_subject.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BangumiScrobbleService', () {
    test('parses search result correctly', () async {
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

    test('getSubject returns BangumiSubject with score and rank', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'id': 12345,
                    'name': 'Demon Slayer',
                    'name_cn': '鬼灭之刃',
                    'summary': 'A boy fights demons to save his sister.',
                    'rating': {'score': 8.2, 'rank': 150, 'total': 1200},
                    'tags': [
                      {'name': '热血', 'count': 100},
                      {'name': '奇幻', 'count': 80},
                    ],
                  },
                ),
              );
            },
          ),
        );

      final service = BangumiScrobbleService(dio);
      final subject = await service.getSubject(12345);
      expect(subject, isNotNull);
      expect(subject!.id, 12345);
      expect(subject.nameCn, '鬼灭之刃');
      expect(subject.score, 8.2);
      expect(subject.rank, 150);
      expect(subject.tags, contains('热血'));
    });

    test('updateCollectionStatus posts correct status', () async {
      int? postedStatus;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              final body = options.data as Map<String, dynamic>?;
              postedStatus = body?['type'] as int?;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {},
                ),
              );
            },
          ),
        );

      final service = BangumiScrobbleService(dio);
      final success = await service.updateCollectionStatus(
        subjectId: 12345,
        collectionType: BangumiCollectionType.doing.value,
        accessToken: 'test_token',
      );
      expect(success, isTrue);
      expect(postedStatus, BangumiCollectionType.doing.value);
    });
  });

  group('BangumiProfile', () {
    test('serializes and deserializes to JSON correctly', () {
      const profile = BangumiProfile(
        userId: 99999,
        username: 'OtakuMaster',
        nickname: '动漫狂人',
        avatarUrl: 'https://bgm.tv/avatar.jpg',
        accessToken: 'access_secret_123',
        autoScrobble: true,
      );

      final json = profile.toJson();
      final revived = BangumiProfile.fromJson(json);

      expect(revived.userId, profile.userId);
      expect(revived.username, profile.username);
      expect(revived.nickname, profile.nickname);
      expect(revived.avatarUrl, profile.avatarUrl);
      expect(revived.accessToken, profile.accessToken);
      expect(revived.autoScrobble, isTrue);
    });
  });

  group('DownloadTaskItem', () {
    test('computes progress, speed format, and copyWith correctly', () {
      final now = DateTime.now();
      final task = DownloadTaskItem(
        id: 'task_001',
        itemId: 'media_100',
        title: 'Episode 01',
        seriesName: 'Frieren',
        seasonNumber: 1,
        episodeNumber: 1,
        url: 'https://example.com/video.mp4',
        savePath: 'F:/downloads/frieren_01.mp4',
        totalBytes: 100000000,
        downloadedBytes: 50000000,
        speedBytesPerSec: 5242880, // 5 MB/s
        status: DownloadTaskStatus.downloading,
        createdAt: now,
      );

      expect(task.progress, closeTo(0.5, 0.001));
      expect(task.formattedSpeed, '5.0 MB/s');
      expect(task.isDownloading, isTrue);
      expect(task.isCompleted, isFalse);
      expect(task.displayTitle, 'Frieren S1E1 · Episode 01');

      final completed = task.copyWith(
        status: DownloadTaskStatus.completed,
        downloadedBytes: 100000000,
        speedBytesPerSec: 0,
      );
      expect(completed.isCompleted, isTrue);
      expect(completed.progress, 1.0);
    });

    test('serializes and deserializes to JSON correctly', () {
      final task = DownloadTaskItem(
        id: 'task_test_1',
        itemId: 'media_999',
        title: 'Movie Test',
        url: 'https://example.com/movie.mp4',
        savePath: 'C:/media/movie.mp4',
        totalBytes: 500000000,
        downloadedBytes: 250000000,
        status: DownloadTaskStatus.paused,
        createdAt: DateTime.parse('2026-09-15T10:00:00.000Z'),
      );

      final json = task.toJson();
      final revived = DownloadTaskItem.fromJson(json);

      expect(revived.id, task.id);
      expect(revived.itemId, task.itemId);
      expect(revived.title, task.title);
      expect(revived.url, task.url);
      expect(revived.savePath, task.savePath);
      expect(revived.totalBytes, task.totalBytes);
      expect(revived.downloadedBytes, task.downloadedBytes);
      expect(revived.status, DownloadTaskStatus.paused);
      expect(revived.createdAt, task.createdAt);
    });
  });
}
