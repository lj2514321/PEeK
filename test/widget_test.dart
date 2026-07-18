import 'package:embyplayer/src/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewportSizes = [
    Size(375, 812),
    Size(768, 900),
    Size(1024, 768),
    Size(1280, 720),
    Size(1440, 900),
  ];

  for (final size in viewportSizes) {
    testWidgets('lays out without overflow at ${size.width.toInt()} pixels', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: EmbyPlayerApp()));
      await tester.pumpAndSettle();

      expect(find.text('让你的片库，\n拥有开场时刻。'), findsOneWidget);
    });
  }

  testWidgets('shows the cinematic server onboarding flow', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EmbyPlayerApp()));

    expect(find.text('让你的片库，\n拥有开场时刻。'), findsOneWidget);
    expect(find.text('添加媒体服务器'), findsOneWidget);
    expect(find.text('PLAYBACK ROUTE'), findsOneWidget);

    await tester.tap(find.text('添加媒体服务器'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('步骤 1 / 2'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);
    expect(find.text('检测并继续'), findsOneWidget);
  });

  testWidgets('opens the server account center from settings', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: EmbyPlayerApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('server-accounts-page')), findsOneWidget);
    expect(find.text('服务器与账户'), findsOneWidget);
    expect(find.text('还没有保存的服务器'), findsOneWidget);
  });
}
