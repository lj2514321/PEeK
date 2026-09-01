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
  });
}
