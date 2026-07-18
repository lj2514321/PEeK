import 'package:flutter/foundation.dart';

abstract final class AppChrome {
  static final immersive = ValueNotifier<bool>(false);

  static void enterImmersive() => immersive.value = true;

  static void leaveImmersive() => immersive.value = false;
}
