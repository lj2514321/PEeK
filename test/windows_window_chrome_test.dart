import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('suppresses the native DWM frame without removing resize support', () {
    final source = File('windows/runner/win32_window.cpp').readAsStringSync();

    expect(source, contains('#define DWMWA_BORDER_COLOR 34'));
    expect(source, contains('#define DWMWA_COLOR_NONE 0xFFFFFFFE'));
    expect(source, contains('#define DWMWA_WINDOW_CORNER_PREFERENCE 33'));
    expect(source, contains('kDwmCornerPreferenceDoNotRound = 1'));
    expect(
      source,
      contains(
        'DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &color_none,',
      ),
    );
    expect(source, contains('WS_OVERLAPPEDWINDOW'));
    expect(
      source,
      contains('DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE,'),
    );
  });

  test('becomes frameless before the first visible Windows frame', () {
    final source = File('lib/main.dart').readAsStringSync();
    final frameless = source.indexOf('await windowManager.setAsFrameless();');
    final removeShadow = source.indexOf(
      'await windowManager.setHasShadow(false);',
    );
    final show = source.indexOf('await windowManager.show();');

    expect(frameless, greaterThanOrEqualTo(0));
    expect(removeShadow, greaterThan(frameless));
    expect(show, greaterThan(removeShadow));
  });

  test('uses floating caption controls without a dedicated titlebar strip', () {
    final source = File('lib/src/app/app.dart').readAsStringSync();

    expect(source, contains('_FramelessWindowSurface'));
    expect(source, contains('DragToResizeArea'));
    expect(source, contains('DragToMoveArea'));
    expect(source, contains('_WindowControls'));
    expect(source, isNot(contains('PEeK  ·  PRIVATE CINEMA')));
    expect(source, isNot(contains('GlassSurface(')));
  });

  test('coordinates fullscreen transitions with the frameless window', () {
    final source = File(
      'lib/src/features/player/presentation/playback_page.dart',
    ).readAsStringSync();

    final restoreHiddenTitlebar = source.indexOf(
      'await windowManager.setTitleBarStyle(',
    );
    final enterFullscreen = source.indexOf(
      'await windowManager.setFullScreen(true);',
    );
    final leaveFullscreen = source.indexOf(
      'await windowManager.setFullScreen(false);',
    );
    final restoreFrameless = source.indexOf(
      'await windowManager.setAsFrameless();',
    );

    expect(restoreHiddenTitlebar, greaterThanOrEqualTo(0));
    expect(enterFullscreen, greaterThan(restoreHiddenTitlebar));
    expect(leaveFullscreen, greaterThan(enterFullscreen));
    expect(restoreFrameless, greaterThan(leaveFullscreen));
    expect(
      RegExp(r'windowManager\.setHasShadow\(false\)').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
  });
}
