import 'package:embyplayer/src/features/player/presentation/playback_pip_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WindowPipController manages pip state correctly', () async {
    final controller = WindowPipController.instance;

    // Initial state
    expect(controller.isPip, isFalse);

    // Toggle on
    final entered = await controller.enterPip();
    expect(entered, isA<bool>());

    // Exit
    final exited = await controller.exitPip();
    expect(exited, isA<bool>());
    expect(controller.isPip, isFalse);
  });
}
