import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/domain/playback_settings.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:flutter/material.dart';

export 'package:embyplayer/src/core/domain/playback_settings.dart'
    show SpatialBackdropTheme;

@immutable
class SpatialAmbientState {
  const SpatialAmbientState({
    this.itemId,
    this.imageUri,
    this.imageHeaders = const {},
    this.paletteSeed = 0,
    this.dominantColor,
    this.theaterBlackout = false,
    this.theme = SpatialBackdropTheme.spatialFlow,
  });

  final String? itemId;
  final Uri? imageUri;
  final Map<String, String> imageHeaders;
  final int paletteSeed;
  final Color? dominantColor;
  final bool theaterBlackout;
  final SpatialBackdropTheme theme;

  SpatialAmbientState copyWith({
    String? itemId,
    Uri? imageUri,
    Map<String, String>? imageHeaders,
    int? paletteSeed,
    Color? dominantColor,
    bool? theaterBlackout,
    SpatialBackdropTheme? theme,
    bool clearImage = false,
    bool clearDominantColor = false,
  }) {
    return SpatialAmbientState(
      itemId: itemId ?? this.itemId,
      imageUri: clearImage ? null : (imageUri ?? this.imageUri),
      imageHeaders: imageHeaders ?? this.imageHeaders,
      paletteSeed: paletteSeed ?? this.paletteSeed,
      dominantColor:
          clearDominantColor ? null : (dominantColor ?? this.dominantColor),
      theaterBlackout: theaterBlackout ?? this.theaterBlackout,
      theme: theme ?? this.theme,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SpatialAmbientState &&
        other.itemId == itemId &&
        other.imageUri == imageUri &&
        other.paletteSeed == paletteSeed &&
        other.dominantColor == dominantColor &&
        other.theaterBlackout == theaterBlackout &&
        other.theme == theme;
  }

  @override
  int get hashCode => Object.hash(
    itemId,
    imageUri,
    paletteSeed,
    dominantColor,
    theaterBlackout,
    theme,
  );
}

class SpatialAmbientController extends ValueNotifier<SpatialAmbientState> {
  SpatialAmbientController._() : super(const SpatialAmbientState());

  static final SpatialAmbientController instance =
      SpatialAmbientController._();

  void update({
    String? itemId,
    Uri? imageUri,
    Map<String, String> imageHeaders = const {},
    int paletteSeed = 0,
    Color? dominantColor,
  }) {
    final next = value.copyWith(
      itemId: itemId,
      imageUri: imageUri,
      imageHeaders: imageHeaders,
      paletteSeed: paletteSeed,
      dominantColor: dominantColor,
    );
    if (value != next) {
      value = next;
    }
  }

  void setTheme(SpatialBackdropTheme theme) {
    if (value.theme != theme) {
      value = value.copyWith(theme: theme);
    }
  }

  void setTheaterBlackout(bool blackout) {
    if (value.theaterBlackout != blackout) {
      value = value.copyWith(theaterBlackout: blackout);
    }
  }
}

class AmbientBackdropScope extends InheritedWidget {
  const AmbientBackdropScope({super.key, required super.child});

  static bool hasAncestor(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AmbientBackdropScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(covariant AmbientBackdropScope oldWidget) => false;
}

abstract final class AppGlass {
  static const radiusSmall = AppRadius.value;
  static const radiusMedium = AppRadius.value;
  static const radiusLarge = AppRadius.value;

  static BoxDecoration decoration({
    double radius = AppRadius.value,
    Color? tint,
    bool elevated = false,
    bool selected = false,
  }) {
    final topAlpha = selected ? 0.28 : (elevated ? 0.18 : 0.14);
    final bottomAlpha = selected ? 0.14 : (elevated ? 0.07 : 0.05);
    final borderAlpha = selected ? 0.52 : (elevated ? 0.34 : 0.26);

    return BoxDecoration(
      color: tint ?? Colors.white.withValues(alpha: bottomAlpha),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: topAlpha),
          Colors.white.withValues(alpha: bottomAlpha),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withValues(alpha: borderAlpha),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: elevated ? 0.36 : 0.22),
          blurRadius: elevated ? 40 : 24,
          offset: Offset(0, elevated ? 16 : 10),
        ),
        if (selected)
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.14),
            blurRadius: 24,
          ),
      ],
    );
  }

  static BoxDecoration visionOSDecoration({
    double radius = AppRadius.value,
    Color? tint,
    bool elevated = true,
    Color? glowColor,
    double borderOpacity = 0.32,
  }) {
    final glow = glowColor ?? Colors.white.withValues(alpha: 0.08);
    return BoxDecoration(
      color: tint ?? Colors.white.withValues(alpha: 0.08),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.06),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withValues(alpha: borderOpacity),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(color: glow, blurRadius: 32, spreadRadius: 0),
        BoxShadow(
          color: Colors.black.withValues(alpha: elevated ? 0.42 : 0.26),
          blurRadius: elevated ? 42 : 24,
          offset: Offset(0, elevated ? 18 : 10),
        ),
      ],
    );
  }
}

/// VisionOS Ambient Glow Container for posters and hero cards.
///
/// Projects a diffuse, softened atmospheric aura behind the foreground card,
/// mimicking the backlight bounce of Apple TV / VisionOS spatial cards.
class PosterAmbientGlow extends StatelessWidget {
  const PosterAmbientGlow({
    super.key,
    required this.child,
    this.glowColor,
    this.borderRadius = AppRadius.value,
    this.blurRadius = 38.0,
    this.spreadRadius = 2.0,
    this.offset = const Offset(0, 12),
  });

  final Widget child;
  final Color? glowColor;
  final double borderRadius;
  final double blurRadius;
  final double spreadRadius;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final glow = glowColor ?? Colors.white.withValues(alpha: 0.14);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: glow,
            blurRadius: blurRadius,
            spreadRadius: spreadRadius,
            offset: offset,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// VisionOS Floating Glass Capsule Island bar.
class VisionGlassCapsuleIsland extends StatelessWidget {
  const VisionGlassCapsuleIsland({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = AppRadius.value,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Container(
      margin:
          margin ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: AppGlass.visionOSDecoration(radius: radius, elevated: true),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                child: const SizedBox.expand(),
              ),
            ),
            Padding(
              padding:
                  padding ??
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// VisionOS 3D Metallic Glass Badge for quality metrics (4K, HDR, Atmos).
class VisionGlassBadge extends StatelessWidget {
  const VisionGlassBadge({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: AppRadius.borderRadius,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.32),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppGlass.radiusMedium,
    this.blur = 28,
    this.tint,
    this.elevated = false,
    this.selected = false,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final Color? tint;
  final bool elevated;
  final bool selected;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    return DecoratedBox(
      decoration: AppGlass.decoration(
        radius: radius,
        tint: tint,
        elevated: elevated,
        selected: selected,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: blur <= 0
            ? content
            : Stack(
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  content,
                ],
              ),
      ),
    );
  }
}

/// Global Apple VisionOS Full-Window Spatial Ambient Backdrop.
///
/// Sits at the root of `HomeShell` behind the sidebar, top bar, and all pages,
/// refracting the active movie's artwork and multi-hue spatial color wash
/// (`暖金环境光` / `赛博紫环境光` / `深空蓝环境光`) across the entire window.
/// Apple VisionOS Full-Window Living Cinema Spatial Ambient Backdrop.
///
/// Features:
/// 1. Dynamic Content-Aware Chromatic Halo: extracts dampened ambient hues from
///    media posters or curated 5-spectrum fluid palettes over obsidian canvas (`#080A10`).
/// 2. 1px Specular Crystal Rim Light: top-left directional specular refraction highlight.
/// 3. Anti-Banding Micro-Dither: high-frequency analog micro-grain eliminating 8-bit gradient rings.
/// 4. Theater Blackout Mode: smooth 680ms dissolve into pure OLED void (`#000000`) during video playback.
/// 5. 5 Spatial Backdrop Themes: `spatialFlow`, `pureOled`, `cyberpunk`, `deepNebula`, `studioGray`.
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop> {
  static ui.Image? _cachedDitherTile;
  static bool _generatingDitherTile = false;

  static const _spatialFlowPalettes = [
    // 0: 暖金琥珀 (Warm Dune Amber / Sunset Cinema)
    _BackdropPalette(
      baseColor: Color(0xFF080A12),
      linearColors: [Color(0xFF6B421B), Color(0xFF33213B), Color(0xFF0F1526)],
      haloColor1: Color(0x666B421B),
      haloColor2: Color(0x3838BDF8),
    ),
    // 1: 极光幽紫 (Aurora Violet / Indigo Nebula)
    _BackdropPalette(
      baseColor: Color(0xFF080A12),
      linearColors: [Color(0xFF542373), Color(0xFF1F2F63), Color(0xFF0C1222)],
      haloColor1: Color(0x607C3AED),
      haloColor2: Color(0x3506B6D4),
    ),
    // 2: 暮色冰蓝 (Twilight Glacial Cyan)
    _BackdropPalette(
      baseColor: Color(0xFF080A12),
      linearColors: [Color(0xFF174F7A), Color(0xFF1E355E), Color(0xFF0B1020)],
      haloColor1: Color(0x550284C7),
      haloColor2: Color(0x3538BDF8),
    ),
    // 3: 苔原林野 (Nordic Forest Pine)
    _BackdropPalette(
      baseColor: Color(0xFF080A12),
      linearColors: [Color(0xFF1B4232), Color(0xFF162B34), Color(0xFF070E16)],
      haloColor1: Color(0x5010B981),
      haloColor2: Color(0x300EA5E9),
    ),
    // 4: 绯红赤霞 (Crimson Sunset Aura)
    _BackdropPalette(
      baseColor: Color(0xFF080A12),
      linearColors: [Color(0xFF5E1E28), Color(0xFF331932), Color(0xFF0D0A14)],
      haloColor1: Color(0x55E11D48),
      haloColor2: Color(0x30F59E0B),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ensureDitherTile();
  }

  void _ensureDitherTile() {
    if (_cachedDitherTile != null || _generatingDitherTile || AppMotion.isTest) {
      return;
    }
    _generatingDitherTile = true;
    const size = 64;
    final pixels = Uint8List(size * size * 4);
    var seed = 0x2468ACE1;
    for (var i = 0; i < size * size; i++) {
      // 32-bit Xorshift PRNG for uniform, deterministic high-frequency noise
      seed ^= (seed << 13) & 0xFFFFFFFF;
      seed ^= (seed >> 17) & 0xFFFFFFFF;
      seed ^= (seed << 5) & 0xFFFFFFFF;
      final lum = seed & 0xFF;
      final idx = i * 4;
      pixels[idx] = lum;
      pixels[idx + 1] = lum;
      pixels[idx + 2] = lum;
      // Ultra-subtle analog grain: ~1.8% to 2.8% alpha to dissolve color banding steps
      pixels[idx + 3] = (lum > 128 ? 7 : 4);
    }
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      (image) {
        _cachedDitherTile = image;
        _generatingDitherTile = false;
        if (mounted) setState(() {});
      },
    );
  }

  _BackdropPalette _resolvePalette(SpatialAmbientState ambient) {
    switch (ambient.theme) {
      case SpatialBackdropTheme.pureOled:
        return const _BackdropPalette(
          baseColor: Color(0xFF000000),
          linearColors: [
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0xFF000000),
          ],
          haloColor1: Colors.transparent,
          haloColor2: Colors.transparent,
        );
      case SpatialBackdropTheme.cyberpunk:
        return const _BackdropPalette(
          baseColor: Color(0xFF070814),
          linearColors: [
            Color(0xFF4C1D66),
            Color(0xFF1B2456),
            Color(0xFF090D1A),
          ],
          haloColor1: Color(0x559333EA),
          haloColor2: Color(0x3506B6D4),
        );
      case SpatialBackdropTheme.deepNebula:
        return const _BackdropPalette(
          baseColor: Color(0xFF060A14),
          linearColors: [
            Color(0xFF0F3B66),
            Color(0xFF15284F),
            Color(0xFF080C16),
          ],
          haloColor1: Color(0x500284C7),
          haloColor2: Color(0x3038BDF8),
        );
      case SpatialBackdropTheme.studioGray:
        return const _BackdropPalette(
          baseColor: Color(0xFF0B0C10),
          linearColors: [
            Color(0xFF242730),
            Color(0xFF181A20),
            Color(0xFF0A0B0E),
          ],
          haloColor1: Color(0x28FFFFFF),
          haloColor2: Color(0x14FFFFFF),
        );
      case SpatialBackdropTheme.spatialFlow:
        if (ambient.dominantColor != null) {
          final hsv = HSVColor.fromColor(ambient.dominantColor!);
          final clampedSat = hsv.saturation.clamp(0.20, 0.32);
          final clampedVal = hsv.value.clamp(0.13, 0.20);
          final c1 = HSVColor.fromAHSV(
            1.0,
            hsv.hue,
            clampedSat,
            clampedVal,
          ).toColor();
          final c2 = HSVColor.fromAHSV(
            1.0,
            (hsv.hue + 24) % 360,
            clampedSat * 0.85,
            clampedVal * 0.72,
          ).toColor();
          const c3 = Color(0xFF080A12);
          return _BackdropPalette(
            baseColor: const Color(0xFF070910),
            linearColors: [c1, c2, c3],
            haloColor1: c1.withValues(alpha: 0.55),
            haloColor2: HSVColor.fromAHSV(
              1.0,
              (hsv.hue + 180) % 360,
              0.32,
              0.16,
            ).toColor().withValues(alpha: 0.28),
          );
        }
        final index =
            ((ambient.itemId?.hashCode.abs() ?? ambient.paletteSeed) +
                ambient.paletteSeed) %
            _spatialFlowPalettes.length;
        return _spatialFlowPalettes[index];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AmbientBackdropScope.hasAncestor(context)) {
      return widget.child;
    }
    return AmbientBackdropScope(
      child: ValueListenableBuilder<SpatialAmbientState>(
        valueListenable: SpatialAmbientController.instance,
        builder: (context, ambient, child) {
          final palette = _resolvePalette(ambient);
          final isPureOled = ambient.theme == SpatialBackdropTheme.pureOled;
          final duration = AppMotion.responsive(
            context,
            const Duration(milliseconds: 680),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              // Cached static RepaintBoundary for spatial ambient backdrop & frost veil
              // Only re-rasterizes when SpatialAmbientState transitions, eliminating idle GPU blur thrashing
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Layer 0: Obsidian Base Canvas
                        DecoratedBox(
                          decoration: BoxDecoration(color: palette.baseColor),
                        ),
                        // Layer 1: Chromatic Halos & Poster Diffuse Layer with Theater Blackout Fade
                        AnimatedOpacity(
                          opacity: (ambient.theaterBlackout || isPureOled)
                              ? 0.0
                              : 1.0,
                          duration: duration,
                          curve: const Cubic(0.16, 1.0, 0.3, 1.0),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimatedSwitcher(
                                duration: duration,
                                switchInCurve: const Cubic(0.16, 1.0, 0.3, 1.0),
                                switchOutCurve: Curves.easeInCubic,
                                child: Stack(
                                  key: ValueKey(
                                    'global-ambient-${ambient.theme.name}-${ambient.itemId ?? 'default'}-${ambient.paletteSeed}',
                                  ),
                                  fit: StackFit.expand,
                                  children: [
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: palette.linearColors,
                                          stops: const [0.0, 0.52, 1.0],
                                        ),
                                      ),
                                    ),
                                    if (ambient.theme ==
                                            SpatialBackdropTheme.spatialFlow &&
                                        ambient.imageUri != null)
                                      Transform.scale(
                                        scale: 1.14,
                                        child: Opacity(
                                          opacity: 0.48,
                                          child: PeekMediaImage(
                                            uri: ambient.imageUri,
                                            headers: ambient.imageHeaders,
                                            kind: PeekMediaImageKind.backdrop,
                                            memCacheWidth: 320,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    if (palette.haloColor1 !=
                                        Colors.transparent)
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: RadialGradient(
                                            center: const Alignment(
                                              -0.38,
                                              -0.48,
                                            ),
                                            radius: 1.15,
                                            colors: [
                                              palette.haloColor1,
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (palette.haloColor2 !=
                                        Colors.transparent)
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: RadialGradient(
                                            center: const Alignment(0.58, 0.44),
                                            radius: 1.05,
                                            colors: [
                                              palette.haloColor2,
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Layer 2: VisionOS Heavy Atmospheric Blur & Vignette
                              BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 42,
                                  sigmaY: 42,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.18),
                                        Colors.black.withValues(alpha: 0.42),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Layer 3: Film Grain / Analog Micro-Dither to eliminate 8-bit banding
                        if (_cachedDitherTile != null && !isPureOled)
                          CustomPaint(
                            painter: _MicroDitherPainter(_cachedDitherTile),
                          ),
                        // Layer 4: 1px Specular Crystal Rim Light highlight border
                        const CustomPaint(
                          painter: _SpecularRimPainter(strokeWidth: 1.0),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _BackdropPalette {
  const _BackdropPalette({
    required this.baseColor,
    required this.linearColors,
    required this.haloColor1,
    required this.haloColor2,
  });

  final Color baseColor;
  final List<Color> linearColors;
  final Color haloColor1;
  final Color haloColor2;
}

/// Directional 1px Specular Crystal Rim Light Painter.
///
/// Simulates physical glass refraction highlight along the window perimeter,
/// falling off gently from top-left to bottom-right.
class _SpecularRimPainter extends CustomPainter {
  const _SpecularRimPainter({this.strokeWidth = 1.0});

  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final half = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      half,
      half,
      math.max(0.0, size.width - strokeWidth),
      math.max(0.0, size.height - strokeWidth),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x33FFFFFF), // ~20% highlight top-left
          Color(0x14FFFFFF), // ~8% highlight mid
          Color(0x05FFFFFF), // ~2% subtle falloff bottom-right
        ],
        stops: [0.0, 0.45, 1.0],
      ).createShader(rect);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _SpecularRimPainter oldDelegate) =>
      strokeWidth != oldDelegate.strokeWidth;
}

/// Anti-Banding Micro-Dither Film Grain Overlay Painter.
class _MicroDitherPainter extends CustomPainter {
  const _MicroDitherPainter(this.tile);

  final ui.Image? tile;

  @override
  void paint(Canvas canvas, Size size) {
    final img = tile;
    if (img == null || size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..shader = ImageShader(
        img,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.identity().storage,
      )
      ..blendMode = BlendMode.screen;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _MicroDitherPainter oldDelegate) =>
      tile != oldDelegate.tile;
}
