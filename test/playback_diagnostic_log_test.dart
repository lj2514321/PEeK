import 'dart:io';

import 'package:embyplayer/src/features/player/data/playback_diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts urls, credentials and sensitive field names', () {
    final sanitized = PlaybackDiagnosticRedactor.sanitizeFields(
      {
        'message':
            'failed https://media.example.test/video?api_key=secret token=secret',
        'authorization': 'MediaBrowser Token="secret"',
        'nested': {
          'path': r'C:\Users\Alex\Videos\movie.mkv',
          'status': 'failed',
        },
      },
      secrets: const ['secret'],
    );
    final text = sanitized.toString();

    expect(text, contains('<redacted-url>'));
    expect(text, contains('token=<redacted>'));
    expect(text, isNot(contains('media.example.test')));
    expect(text, isNot(contains(r'C:\Users\Alex')));
    expect(text, isNot(contains('secret')));
  });

  test('writes structured logs without playback secrets', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peek-diagnostics-log-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final log = PlaybackDiagnosticLog(
      directory: directory,
      now: () => DateTime.utc(2026, 7, 19, 8, 30),
    );

    await log.write(
      'player_error',
      fields: const {
        'playbackMethod': 'directPlay',
        'message': 'cannot open https://media.example.test/file?token=secret',
        'itemId': 'private-item',
      },
      secrets: const ['secret'],
    );

    final contents = await log.currentFile.readAsString();
    expect(contents, contains('2026-07-19T08:30:00.000Z'));
    expect(contents, contains('directPlay'));
    expect(contents, contains('<redacted-url>'));
    expect(contents, isNot(contains('media.example.test')));
    expect(contents, isNot(contains('private-item')));
    expect(contents, isNot(contains('secret')));
  });

  test('rotates the active diagnostics log at the size limit', () async {
    final directory = await Directory.systemTemp.createTemp(
      'peek-diagnostics-log-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final log = PlaybackDiagnosticLog(directory: directory, maxBytes: 180);

    await log.write('first', fields: {'message': 'a' * 120});
    await log.write('second', fields: {'message': 'b' * 120});

    expect(await log.currentFile.exists(), isTrue);
    expect(await log.previousFile.exists(), isTrue);
    expect(await log.currentFile.readAsString(), contains('second'));
    expect(await log.previousFile.readAsString(), contains('first'));
  });
}
