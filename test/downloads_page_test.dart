import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/download/presentation/downloads_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DownloadsPage displays header, tabs, and empty states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: DownloadsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('离线下载中心'), findsOneWidget);
    expect(find.text('传输中'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('没有正在进行的下载任务'), findsOneWidget);

    // Switch to completed tab
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();

    expect(find.text('暂无已下载完成的离线媒体'), findsOneWidget);
  });
}
