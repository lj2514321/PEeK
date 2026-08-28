import 'package:embyplayer/src/features/dedupe/data/duplicate_detector_service.dart';
import 'package:embyplayer/src/features/dedupe/domain/duplicate_media_group.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = DuplicateDetectorService();

  group('DuplicateDetectorService - normalizeTitle', () {
    test('cleans quality, edition tags, and punctuation', () {
      expect(
        service.normalizeTitle('Inception [2010] [4K Remux HEVC TrueHD Atmos]'),
        'inception 2010',
      );
      expect(
        service.normalizeTitle('The Dark Knight (1080p BluRay x264 DTS)'),
        'the dark knight',
      );
      expect(
        service.normalizeTitle('【4K HDR 杜比视界】流浪地球2 [Extended Cut]'),
        '流浪地球2',
      );
      expect(
        service.normalizeTitle('Fight.Club.1999.1080p.Web-dl.H264'),
        'fight club 1999',
      );
    });
  });

  group('DuplicateDetectorService - calculateQualityMetrics', () {
    test('evaluates 4K HDR HEVC item with higher score than 1080p H264', () {
      const item4K = MediaItem(
        id: '1',
        name: 'Inception 4K HDR',
        kind: MediaItemKind.movie,
        width: 3840,
        height: 2160,
        videoCodec: 'HEVC',
        fileSize: 45 * 1024 * 1024 * 1024,
      );

      const item1080p = MediaItem(
        id: '2',
        name: 'Inception 1080p',
        kind: MediaItemKind.movie,
        width: 1920,
        height: 1080,
        videoCodec: 'H264',
        fileSize: 6 * 1024 * 1024 * 1024,
      );

      final metrics4K = service.calculateQualityMetrics(item4K);
      final metrics1080p = service.calculateQualityMetrics(item1080p);

      expect(metrics4K.is4K, isTrue);
      expect(metrics4K.isHDR, isTrue);
      expect(metrics4K.videoCodec, 'HEVC');
      expect(metrics4K.qualityScore, greaterThan(metrics1080p.qualityScore));

      expect(metrics1080p.is4K, isFalse);
      expect(metrics1080p.resolutionLabel, '1080p FHD');
    });
  });

  group('DuplicateDetectorService - findDuplicates', () {
    test('groups items by TMDb Provider ID and recommends highest quality', () {
      const itemA = MediaItem(
        id: 'item-a',
        name: 'Interstellar 1080p',
        kind: MediaItemKind.movie,
        productionYear: 2014,
        providerIds: {'Tmdb': '157336'},
        width: 1920,
        height: 1080,
        fileSize: 8 * 1024 * 1024 * 1024,
      );

      const itemB = MediaItem(
        id: 'item-b',
        name: 'Interstellar 4K Remux',
        kind: MediaItemKind.movie,
        productionYear: 2014,
        providerIds: {'Tmdb': '157336'},
        width: 3840,
        height: 2160,
        fileSize: 60 * 1024 * 1024 * 1024,
      );

      const itemOther = MediaItem(
        id: 'item-other',
        name: 'Tenet',
        kind: MediaItemKind.movie,
        productionYear: 2020,
        providerIds: {'Tmdb': '577922'},
      );

      final groups = service.findDuplicates([itemA, itemB, itemOther]);

      expect(groups.length, 1);
      final group = groups.first;
      expect(group.matchReason, DuplicateMatchReason.providerId);
      expect(group.matchDetail, 'TMDb ID: 157336');
      expect(group.items.length, 2);
      expect(group.recommendedKeepId, 'item-b'); // 4K has higher score
      expect(group.selectedDeleteIds, {'item-a'});
    });

    test('groups episodes with identical series, season and episode number', () {
      const ep1 = MediaItem(
        id: 'ep-1',
        name: 'Breaking Bad S01E01 720p',
        kind: MediaItemKind.episode,
        seriesName: 'Breaking Bad',
        parentIndexNumber: 1,
        indexNumber: 1,
        fileSize: 1 * 1024 * 1024 * 1024,
      );

      const ep2 = MediaItem(
        id: 'ep-2',
        name: 'Breaking Bad S01E01 1080p',
        kind: MediaItemKind.episode,
        seriesName: 'Breaking Bad',
        parentIndexNumber: 1,
        indexNumber: 1,
        width: 1920,
        height: 1080,
        fileSize: 3 * 1024 * 1024 * 1024,
      );

      final groups = service.findDuplicates([ep1, ep2]);

      expect(groups.length, 1);
      final group = groups.first;
      expect(group.matchReason, DuplicateMatchReason.episode);
      expect(group.recommendedKeepId, 'ep-2');
    });

    test('skips groups in ignoredGroupIds whitelist', () {
      const itemA = MediaItem(
        id: 'item-a',
        name: 'Matrix 1080p',
        kind: MediaItemKind.movie,
        providerIds: {'Tmdb': '603'},
      );

      const itemB = MediaItem(
        id: 'item-b',
        name: 'Matrix 4K',
        kind: MediaItemKind.movie,
        providerIds: {'Tmdb': '603'},
      );

      final groups = service.findDuplicates(
        [itemA, itemB],
        ignoredGroupIds: {'tmdb:603'},
      );

      expect(groups, isEmpty);
    });
  });
}
