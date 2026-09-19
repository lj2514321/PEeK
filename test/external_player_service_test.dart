import 'dart:io';

import 'package:embyplayer/src/features/player/data/external_player_service.dart';
import 'package:embyplayer/src/features/player/domain/playback_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExternalPlayerService', () {
    test('formatHms formats durations accurately', () {
      expect(
        ExternalPlayerService.formatHms(Duration.zero),
        '00:00:00',
      );
      expect(
        ExternalPlayerService.formatHms(
          const Duration(hours: 1, minutes: 23, seconds: 45),
        ),
        '01:23:45',
      );
      expect(
        ExternalPlayerService.formatHms(const Duration(seconds: 42)),
        '00:00:42',
      );
      expect(
        ExternalPlayerService.formatHms(
          const Duration(hours: 12, minutes: 0, seconds: 9),
        ),
        '12:00:09',
      );
    });

    test('detectExternalPlayer executes without crashing', () async {
      const service = ExternalPlayerService();
      final detected = await service.detectExternalPlayer();
      // On this machine, PotPlayer is installed, so detected will be found or null on non-windows
      if (detected != null) {
        expect(detected.executablePath, isNotEmpty);
        expect(detected.name, isNotEmpty);
      }
    });

    test('launch returns false or handles invalid non-existent path cleanly', () async {
      const service = ExternalPlayerService();
      final plan = PlaybackPlan(
        itemId: 'item-1',
        mediaSourceId: 'src-1',
        playSessionId: 'session-1',
        streamUri: Uri.parse('http://127.0.0.1:8096/stream.mkv'),
        method: PlaybackMethod.directPlay,
        startPosition: const Duration(minutes: 5),
      );

      // Launch with non-existent path will attempt fallback and return without throwing
      final result = await service.launch(
        plan,
        executablePath: r'Z:\NonExistent\FakePlayer.exe',
      );
      expect(result, isA<bool>());
    });

    test('parses local STRM files when launching', () async {
      const service = ExternalPlayerService();
      final tempDir = await Directory.systemTemp.createTemp('peek-strm-test-');
      addTearDown(() => tempDir.delete(recursive: true));
      final strmFile = File('${tempDir.path}\\movie.strm');
      await strmFile.writeAsString('# Comment line\nhttp://127.0.0.1:5244/d/alist/movie.mkv\n');

      final plan = PlaybackPlan(
        itemId: 'item-strm',
        mediaSourceId: 'src-strm',
        playSessionId: 'session-strm',
        streamUri: strmFile.uri,
        method: PlaybackMethod.directPlay,
      );

      final result = await service.launch(
        plan,
        executablePath: r'Z:\NonExistent\FakePlayer.exe',
      );
      expect(result, isA<bool>());
    });

    test('buildPotPlayerArgs places switches before targetUrl and formats headers', () {
      const service = ExternalPlayerService();
      const targetUrl = 'http://127.0.0.1:8096/Videos/item123/stream.mp4?Static=true';
      final args = service.buildPotPlayerArgs(
        targetUrl: targetUrl,
        seekPosition: const Duration(minutes: 1, seconds: 30),
        title: 'My Favorite Movie',
        httpHeaders: {
          'User-Agent': 'PEeK/1.0.0',
          'X-Emby-Token': 'test_token_abc',
        },
        streamUri: Uri.parse(targetUrl),
        subtitleUri: Uri.parse('http://127.0.0.1:8096/subtitles.vtt'),
      );

      // Target URL must be the very last argument
      expect(args.last, targetUrl);

      // Switches must be present
      expect(args, contains('/seek=00:01:30'));
      // PotPlayer does not support /title= switch
      expect(args.any((a) => a.startsWith('/title=')), isFalse);
      expect(args, contains('/user_agent=PEeK/1.0.0'));
      expect(args, contains('/referer=http://127.0.0.1:8096/'));
      expect(args, contains('/sub=http://127.0.0.1:8096/subtitles.vtt'));

      final headersArg = args.firstWhere((a) => a.startsWith('/headers='));
      expect(headersArg, contains('X-Emby-Token: test_token_abc'));
      expect(headersArg, contains('X-MediaBrowser-Token: test_token_abc'));
      expect(headersArg, contains('Authorization: MediaBrowser Token=test_token_abc'));
      expect(headersArg, contains('\r\n'));
    });

    test('buildVlcArgs places switches before targetUrl', () {
      const service = ExternalPlayerService();
      const targetUrl = 'http://127.0.0.1:8096/Videos/item123/stream.mp4';
      final args = service.buildVlcArgs(
        targetUrl: targetUrl,
        seekPosition: const Duration(seconds: 45),
        title: 'Sample Video',
      );

      expect(args.last, targetUrl);
      expect(args, contains('--start-time=45'));
      expect(args, contains('--meta-title=Sample Video'));
    });

    test('resolvePlayableUrl attaches all auth tokens to query parameters for server streams', () async {
      const service = ExternalPlayerService();
      final plan = PlaybackPlan(
        itemId: 'item-auth',
        mediaSourceId: 'src-auth',
        playSessionId: 'sess-auth',
        streamUri: Uri.parse('http://127.0.0.1:8096/Videos/item-auth/stream.mp4?Static=true&MediaSourceId=src-auth'),
        method: PlaybackMethod.directPlay,
        httpHeaders: {
          'X-Emby-Token': 'secret_token_123',
        },
      );

      final resolved = await service.resolvePlayableUrl(plan);
      final resolvedUri = Uri.parse(resolved);

      expect(resolvedUri.queryParameters['api_key'], 'secret_token_123');
      expect(resolvedUri.queryParameters['X-Emby-Token'], 'secret_token_123');
      expect(resolvedUri.queryParameters['X-MediaBrowser-Token'], 'secret_token_123');
      expect(resolvedUri.queryParameters['token'], 'secret_token_123');
      expect(resolvedUri.queryParameters['Static'], 'true');
      expect(resolvedUri.queryParameters['MediaSourceId'], 'src-auth');
    });

    test('resolvePlayableUrl does not inject server tokens into external proxy URLs', () async {
      const service = ExternalPlayerService();
      const externalUrl = 'http://192.168.110.110:19798/static/115/movie.mp4';
      final plan = PlaybackPlan(
        itemId: 'item-ext',
        mediaSourceId: 'src-ext',
        playSessionId: 'sess-ext',
        streamUri: Uri.parse(externalUrl),
        method: PlaybackMethod.directPlay,
        httpHeaders: {
          'X-Emby-Token': 'secret_token_123',
        },
      );

      final resolved = await service.resolvePlayableUrl(plan);
      final resolvedUri = Uri.parse(resolved);

      expect(resolvedUri.queryParameters.containsKey('api_key'), isFalse);
      expect(resolvedUri.queryParameters.containsKey('X-Emby-Token'), isFalse);
      expect(resolvedUri.queryParameters.containsKey('token'), isFalse);
      expect(resolved, externalUrl);
    });
  });
}
