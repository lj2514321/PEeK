import 'package:embyplayer/src/features/player/domain/playback_source_transition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const transition = PlaybackSourceTransition();

  test('switches after preparing and opening the next source', () async {
    var restoreCount = 0;

    final result = await transition.execute<String>(
      prepare: () async => 'next-plan',
      open: (value) async => expect(value, 'next-plan'),
      restore: () async => restoreCount++,
    );

    expect(result.status, PlaybackSourceTransitionStatus.switched);
    expect(result.value, 'next-plan');
    expect(restoreCount, 0);
  });

  test('does not replace or restore when preparation fails', () async {
    var openCount = 0;
    var restoreCount = 0;

    final result = await transition.execute<String>(
      prepare: () async => throw StateError('playback info failed'),
      open: (_) async => openCount++,
      restore: () async => restoreCount++,
    );

    expect(result.status, PlaybackSourceTransitionStatus.preparationFailed);
    expect(result.error, isA<StateError>());
    expect(openCount, 0);
    expect(restoreCount, 0);
  });

  test('restores the previous source when opening fails', () async {
    var restoreCount = 0;

    final result = await transition.execute<String>(
      prepare: () async => 'next-plan',
      open: (_) async => throw StateError('open failed'),
      restore: () async => restoreCount++,
    );

    expect(result.status, PlaybackSourceTransitionStatus.restored);
    expect(result.error, isA<StateError>());
    expect(restoreCount, 1);
  });

  test('reports when both the next and previous source fail', () async {
    final result = await transition.execute<String>(
      prepare: () async => 'next-plan',
      open: (_) async => throw StateError('open failed'),
      restore: () async => throw StateError('restore failed'),
    );

    expect(result.status, PlaybackSourceTransitionStatus.restoreFailed);
    expect(result.error, isA<StateError>());
    expect(result.restoreError, isA<StateError>());
  });
}
