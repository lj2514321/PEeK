import 'package:cached_network_image/cached_network_image.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

enum PeekMediaImageKind { poster, backdrop, episode, person, library }

abstract final class PeekMediaImageCache {
  static const cacheName = 'peek_media_images_v1';
  static const stalePeriod = Duration(days: 30);
  static const maxObjects = 600;
  static const _secretQueryNames = {
    'api_key',
    'apikey',
    'access_token',
    'token',
  };

  static final BaseCacheManager instance = CacheManager(
    Config(
      cacheName,
      stalePeriod: stalePeriod,
      maxNrOfCacheObjects: maxObjects,
    ),
  );

  static String keyFor(Uri uri) {
    final safeQuery = <String, List<String>>{};
    for (final entry in uri.queryParametersAll.entries) {
      if (!_secretQueryNames.contains(entry.key.toLowerCase())) {
        safeQuery[entry.key] = entry.value;
      }
    }
    return uri
        .replace(userInfo: '', queryParameters: safeQuery)
        .normalizePath()
        .toString();
  }

  static Future<void> clear() => instance.emptyCache();
}

class PeekMediaImage extends StatelessWidget {
  const PeekMediaImage({
    super.key,
    required this.uri,
    this.headers = const {},
    this.kind = PeekMediaImageKind.poster,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.placeholderIconColor = AppColors.textTertiary,
    this.placeholderBackground,
    this.placeholderIconSize,
    this.placeholderIcon,
    this.cacheManager,
  });

  final Uri? uri;
  final Map<String, String> headers;
  final PeekMediaImageKind kind;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final Color placeholderIconColor;
  final Color? placeholderBackground;
  final double? placeholderIconSize;
  final IconData? placeholderIcon;
  final BaseCacheManager? cacheManager;

  @override
  Widget build(BuildContext context) {
    final imageUri = uri;
    if (imageUri == null) {
      return _placeholder(loading: false, failed: false);
    }

    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return CachedNetworkImage(
      imageUrl: imageUri.toString(),
      httpHeaders: headers,
      cacheManager: cacheManager ?? PeekMediaImageCache.instance,
      cacheKey: PeekMediaImageCache.keyFor(imageUri),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      // Jellyfin/Emby URLs already request an appropriate maxWidth. Supplying
      // disk resize dimensions here would require an ImageCacheManager and
      // makes a plain custom CacheManager fail every image in debug builds.
      useOldImageOnUrlChange: true,
      placeholderFadeInDuration: Duration.zero,
      fadeOutDuration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 90),
      fadeInDuration: disableAnimations ? Duration.zero : AppMotion.fast,
      placeholder: (_, _) => _placeholder(loading: true, failed: false),
      errorWidget: (_, _, _) => _placeholder(loading: false, failed: true),
    );
  }

  Widget _placeholder({required bool loading, required bool failed}) {
    final icon = failed
        ? Icons.broken_image_outlined
        : placeholderIcon ?? _iconFor(kind);
    final iconOpacity = loading ? 0.42 : 0.72;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: placeholderBackground ?? AppColors.surfaceLow,
        gradient: placeholderBackground == null
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.surfaceHigh, AppColors.surfaceLow],
              )
            : null,
      ),
      child: Center(
        child: Icon(
          icon,
          size: placeholderIconSize ?? _iconSizeFor(kind),
          color: placeholderIconColor.withValues(alpha: iconOpacity),
        ),
      ),
    );
  }
}

IconData _iconFor(PeekMediaImageKind kind) {
  return switch (kind) {
    PeekMediaImageKind.poster => Icons.movie_outlined,
    PeekMediaImageKind.backdrop => Icons.local_movies_outlined,
    PeekMediaImageKind.episode => Icons.live_tv_outlined,
    PeekMediaImageKind.person => Icons.person_rounded,
    PeekMediaImageKind.library => Icons.video_library_rounded,
  };
}

double _iconSizeFor(PeekMediaImageKind kind) {
  return switch (kind) {
    PeekMediaImageKind.backdrop => 72,
    PeekMediaImageKind.person => 30,
    PeekMediaImageKind.poster ||
    PeekMediaImageKind.episode ||
    PeekMediaImageKind.library => 38,
  };
}
