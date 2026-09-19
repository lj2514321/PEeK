import 'package:embyplayer/src/features/servers/data/emby_media_item_parser.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final server = DiscoveredServer(
    kind: ServerKind.emby,
    name: 'Cinema Server',
    version: '4.8.0.0',
    serverId: 'server-1',
    apiBaseUri: Uri.parse('http://127.0.0.1:8096'),
  );
  final account = AuthenticatedServer(
    server: server,
    userId: 'user-1',
    userName: 'admin',
    deviceId: 'device-1',
    accessToken: 'token-123',
  );

  test('EmbyMediaItemParser parses complex MediaItem DTO with people and chapters', () {
    final rawItem = {
      'Id': 'movie-101',
      'Name': 'Inception',
      'Type': 'Movie',
      'Overview': 'A thief who steals corporate secrets...',
      'ProductionYear': 2010,
      'RunTimeTicks': 88800000000,
      'ImageTags': {'Primary': 'tag-primary'},
      'BackdropImageTags': ['tag-backdrop'],
      'UserData': {
        'PlaybackPositionTicks': 1200000000,
        'Played': true,
        'IsFavorite': true,
      },
      'Chapters': [
        {'StartPositionTicks': 0, 'Name': 'Intro'},
        {'StartPositionTicks': 300000000, 'Name': 'Dream Level 1'},
      ],
      'People': [
        {
          'Id': 'actor-1',
          'Name': 'Leonardo DiCaprio',
          'Type': 'Actor',
          'Role': 'Cobb',
          'PrimaryImageTag': 'tag-leo',
        }
      ],
      'Genres': ['Sci-Fi', 'Action'],
      'CommunityRating': 8.8,
      'OfficialRating': 'PG-13',
    };

    final item = EmbyMediaItemParser.parseItem(rawItem, account);

    expect(item.id, 'movie-101');
    expect(item.name, 'Inception');
    expect(item.kind, MediaItemKind.movie);
    expect(item.productionYear, 2010);
    expect(item.played, isTrue);
    expect(item.favorite, isTrue);
    expect(item.chapters.length, 2);
    expect(item.chapters[0].name, 'Intro');
    expect(item.people.length, 1);
    expect(item.people.first.name, 'Leonardo DiCaprio');
    expect(item.people.first.role, 'Cobb');
    expect(item.genres, contains('Sci-Fi'));
    expect(item.communityRating, 8.8);
  });

  test('EmbyMediaItemParser maps BoxSet to browsable folder kind', () {
    final rawBoxSet = {
      'Id': 'boxset-202',
      'Name': 'Actor Collection',
      'Type': 'BoxSet',
    };

    final item = EmbyMediaItemParser.parseItem(rawBoxSet, account);

    expect(item.id, 'boxset-202');
    expect(item.name, 'Actor Collection');
    expect(item.kind, MediaItemKind.folder);
  });

  test('EmbyMediaItemParser parses multiple MediaSources for version switching', () {
    final rawItem = {
      'Id': 'movie-multi-version',
      'Name': 'Dune 2',
      'Type': 'Movie',
      'MediaSources': [
        {
          'Id': 'source-4k',
          'Name': '4K HDR Remux',
          'Container': 'mkv',
          'Size': 25000000000,
          'Bitrate': 45000000,
          'Path': '/media/dune2_4k.mkv',
          'MediaStreams': [
            {
              'Type': 'Video',
              'Codec': 'hevc',
              'Width': 3840,
              'Height': 2160,
              'VideoRange': 'HDR',
            },
            {
              'Type': 'Audio',
              'Codec': 'truehd',
            },
          ],
        },
        {
          'Id': 'source-1080p',
          'Name': '1080P 高清',
          'Container': 'mp4',
          'Size': 4000000000,
          'Bitrate': 8000000,
          'Path': '/media/dune2_1080p.mp4',
          'MediaStreams': [
            {
              'Type': 'Video',
              'Codec': 'h264',
              'Width': 1920,
              'Height': 1080,
            },
            {
              'Type': 'Audio',
              'Codec': 'aac',
            },
          ],
        },
      ],
    };

    final item = EmbyMediaItemParser.parseItem(rawItem, account);

    expect(item.mediaSources.length, 2);
    expect(item.mediaSources[0].id, 'source-4k');
    expect(item.mediaSources[0].name, '4K HDR Remux');
    expect(item.mediaSources[0].resolutionLabel, '4K');
    expect(item.mediaSources[0].videoCodec, 'hevc');
    expect(item.mediaSources[0].videoRange, 'HDR');
    expect(item.mediaSources[0].audioCodec, 'truehd');
    expect(item.mediaSources[0].formattedFileSize, '23.3 GB');

    expect(item.mediaSources[1].id, 'source-1080p');
    expect(item.mediaSources[1].name, '1080P 高清');
    expect(item.mediaSources[1].resolutionLabel, '1080P');
    expect(item.mediaSources[1].videoCodec, 'h264');
    expect(item.mediaSources[1].formattedFileSize, '3.7 GB');
  });
}
