import 'package:flutter/foundation.dart';

abstract final class AppChrome {
  static const windowControlsWidth = 138.0;
  static const windowControlsHeight = 38.0;

  static final immersive = ValueNotifier<bool>(false);

  static void enterImmersive() => immersive.value = true;

  static void leaveImmersive() => immersive.value = false;
}
