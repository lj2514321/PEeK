import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class AppChrome {
  static const windowControlsWidth = 136.0;
  static const windowControlsHeight = 54.0;

  static final immersive = ValueNotifier<bool>(false);

  static void enterImmersive() {
    immersive.value = true;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  static void leaveImmersive() {
    immersive.value = false;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}
