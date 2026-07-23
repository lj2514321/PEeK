import 'package:embyplayer/src/features/player/presentation/playback_interaction_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hides controls after the configured idle delay', (tester) async {
    var active = true;
    var canAutoHide = true;
    var visibilityChanges = 0;
    final coordinator = PlaybackInteractionCoordinator(
      canShowControls: () => true,
      canAutoHideControls: () => canAutoHide,
      isActive: () => active,
      onControlsShown: () {},
      onControlsVisibilityChanged: () => visibilityChanges++,
      controlsHideDelay: const Duration(milliseconds: 100),
    );
    addTearDown(coordinator.dispose);

    coordinator.scheduleControlsHide();
    await tester.pump(const Duration(milliseconds: 99));
    expect(coordinator.controlsVisible, isTrue);

    await tester.pump(const Duration(milliseconds: 1));
    expect(coordinator.controlsVisible, isFalse);
    expect(visibilityChanges, 1);

    coordinator.showControls();
    expect(coordinator.controlsVisible, isTrue);
    canAutoHide = false;
    coordinator.scheduleControlsHide();
    await tester.pump(const Duration(milliseconds: 150));
    expect(coordinator.controlsVisible, isTrue);

    active = false;
    coordinator.hideControls(force: true);
    expect(coordinator.controlsVisible, isTrue);
  });

  testWidgets('coalesces repeated relative seeks and clears feedback', (
    tester,
  ) async {
    final committed = <Duration>[];
    var afterCommitCount = 0;
    final coordinator = PlaybackInteractionCoordinator(
      canShowControls: () => true,
      canAutoHideControls: () => false,
      isActive: () => true,
      onControlsShown: () {},
      onControlsVisibilityChanged: () {},
      seekCommitDelay: const Duration(milliseconds: 100),
      seekFeedbackDuration: const Duration(milliseconds: 300),
    );
    addTearDown(coordinator.dispose);

    coordinator.queueRelativeSeek(
      base: Duration.zero,
      offset: const Duration(seconds: 10),
      duration: const Duration(minutes: 2),
      commit: (target) async => committed.add(target),
      afterCommitted: () async => afterCommitCount++,
    );
    coordinator.queueRelativeSeek(
      base: coordinator.pendingSeekTarget!,
      offset: const Duration(seconds: 10),
      duration: const Duration(minutes: 2),
      commit: (target) async => committed.add(target),
      afterCommitted: () async => afterCommitCount++,
    );

    expect(coordinator.seekFeedback.value?.deltaSeconds, 20);
    expect(
      coordinator.seekFeedback.value?.position,
      const Duration(seconds: 20),
    );

    await tester.pump(const Duration(milliseconds: 99));
    expect(committed, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(committed, [const Duration(seconds: 20)]);
    expect(afterCommitCount, 1);

    await tester.pump(const Duration(milliseconds: 200));
    expect(coordinator.seekFeedback.value, isNull);
  });
}
