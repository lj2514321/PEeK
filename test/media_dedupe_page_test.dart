import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/dedupe/data/duplicate_ignored_store.dart';
import 'package:embyplayer/src/features/dedupe/presentation/media_dedupe_page.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders MediaDedupePage and detects duplicate items', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final memoryStore = MemoryDuplicateIgnoredStore();

    const item1 = MediaItem(
      id: 'd-1',
      name: '奥本海默 1080p',
      kind: MediaItemKind.movie,
      productionYear: 2023,
      providerIds: {'Tmdb': '872585'},
      width: 1920,
      height: 1080,
      fileSize: 5 * 1024 * 1024 * 1024,
    );

    const item2 = MediaItem(
      id: 'd-2',
      name: '奥本海默 4K HDR',
      kind: MediaItemKind.movie,
      productionYear: 2023,
      providerIds: {'Tmdb': '872585'},
      width: 3840,
      height: 2160,
      fileSize: 40 * 1024 * 1024 * 1024,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          duplicateIgnoredStoreProvider.overrideWithValue(memoryStore),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const MediaDedupePage(
            account: null,
            initialItems: [item1, item2],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify title and metrics
    expect(find.text('媒体库查重与智能去重'), findsOneWidget);
    expect(find.text('发现重复组'), findsOneWidget);
    expect(find.text('1 组'), findsOneWidget);

    // Verify group contents
    expect(find.text('奥本海默 1080p'), findsWidgets);
    expect(find.text('推荐保留 (优质)'), findsOneWidget);
    expect(find.text('冗余拷贝'), findsOneWidget);
    expect(find.text('TMDb ID: 872585'), findsOneWidget);

    // Test ignoring group
    await tester.tap(find.text('忽略此组'));
    await tester.pumpAndSettle();

    // Should now show empty state
    expect(find.text('太棒了！媒体库未发现任何冗余重复内容'), findsOneWidget);
  });
}
