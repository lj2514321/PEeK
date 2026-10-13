import 'package:cached_network_image/cached_network_image.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('separates cache entries by server origin and image tag', () {
    final firstServer = Uri.parse(
      'http://192.168.1.10:8096/Items/movie/Images/Primary?tag=one',
    );
    final secondServer = Uri.parse(
      'http://192.168.1.11:8096/Items/movie/Images/Primary?tag=one',
    );
    final changedImage = Uri.parse(
      'http://192.168.1.10:8096/Items/movie/Images/Primary?tag=two',
    );

    expect(
      PeekMediaImageCache.keyFor(firstServer),
      isNot(PeekMediaImageCache.keyFor(secondServer)),
    );
    expect(
      PeekMediaImageCache.keyFor(firstServer),
      isNot(PeekMediaImageCache.keyFor(changedImage)),
    );
  });

  test('removes credentials from image cache keys', () {
    final uri = Uri.parse(
      'http://user:password@server:8096/Items/movie/Images/Primary'
      '?tag=frame&api_key=private-key&token=private-token',
    );

    final cacheKey = PeekMediaImageCache.keyFor(uri);

    expect(cacheKey, contains('tag=frame'));
    expect(cacheKey, isNot(contains('user')));
    expect(cacheKey, isNot(contains('password')));
    expect(cacheKey, isNot(contains('private-key')));
    expect(cacheKey, isNot(contains('private-token')));
  });

  test('uses the bounded PEeK media image cache policy', () {
    expect(PeekMediaImageCache.stalePeriod, const Duration(days: 30));
    expect(PeekMediaImageCache.maxObjects, 600);
  });

  testWidgets('renders a media-specific placeholder without a URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: SizedBox.square(
            dimension: 80,
            child: PeekMediaImage(uri: null, kind: PeekMediaImageKind.person),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a file image provider for local artwork', (tester) async {
    late Widget builtImage;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) {
            builtImage = PeekMediaImage(
              uri: Uri.file(r'C:\Media\poster.jpg', windows: true),
            ).build(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final provider = (builtImage as Image).image;
    final resolvedProvider =
        provider is ResizeImage ? provider.imageProvider : provider;
    expect(resolvedProvider, isA<FileImage>());
  });

  testWidgets('uses the basic cache manager without client-side resizing', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final uri = Uri.parse(
      'http://192.168.1.10:8096/Items/movie/Images/Backdrop?tag=frame',
    );
    late CachedNetworkImage builtImage;
    final cacheManager = _FakeCacheManager();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) {
            builtImage =
                PeekMediaImage(
                      uri: uri,
                      headers: const {'X-Emby-Token': 'private-token'},
                      kind: PeekMediaImageKind.backdrop,
                      cacheManager: cacheManager,
                    ).build(context)
                    as CachedNetworkImage;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(builtImage.httpHeaders, const {'X-Emby-Token': 'private-token'});
    expect(builtImage.cacheKey, uri.toString());
    expect(builtImage.cacheKey, isNot(contains('private-token')));
    expect(builtImage.fadeInDuration, Duration.zero);
    expect(builtImage.fadeOutDuration, Duration.zero);
    expect(builtImage.maxWidthDiskCache, isNull);
    expect(builtImage.maxHeightDiskCache, isNull);
  });
}

class _FakeCacheManager implements BaseCacheManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
