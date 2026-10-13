import 'dart:ui';

import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/core/presentation/peek_media_image.dart';
import 'package:flutter/material.dart';

@immutable
class SpatialAmbientState {
  const SpatialAmbientState({
    this.itemId,
    this.imageUri,
    this.imageHeaders = const {},
    this.paletteSeed = 0,
  });

  final String? itemId;
  final Uri? imageUri;
  final Map<String, String> imageHeaders;
  final int paletteSeed;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SpatialAmbientState &&
        other.itemId == itemId &&
        other.imageUri == imageUri &&
        other.paletteSeed == paletteSeed;
  }

  @override
  int get hashCode => Object.hash(itemId, imageUri, paletteSeed);
}

class SpatialAmbientController extends ValueNotifier<SpatialAmbientState> {
  SpatialAmbientController._() : super(const SpatialAmbientState());

  static final SpatialAmbientController instance = SpatialAmbientController._();

  void update({
    String? itemId,
    Uri? imageUri,
    Map<String, String> imageHeaders = const {},
    int paletteSeed = 0,
  }) {
    final next = SpatialAmbientState(
      itemId: itemId,
      imageUri: imageUri,
      imageHeaders: imageHeaders,
      paletteSeed: paletteSeed,
    );
    if (value != next) {
      value = next;
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
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop> {
  static const _ambientThemes = [
    // 0: 暖金沙漠环境光 (Warm Dune Amber / Sunset Cinema)
    [Color(0xFF6B421B), Color(0xFF33213B), Color(0xFF101729)],
    // 1: 赛博霓虹紫环境光 (Cyberpunk Violet / Indigo Nebula)
    [Color(0xFF542373), Color(0xFF1F2F63), Color(0xFF0D1324)],
    // 2: 深空星云蓝环境光 (Interstellar Deep Nebula Blue / Cyan)
    [Color(0xFF174F7A), Color(0xFF1E355E), Color(0xFF0C1222)],
  ];

  @override
  Widget build(BuildContext context) {
    return AmbientBackdropScope(
      child: ValueListenableBuilder<SpatialAmbientState>(
        valueListenable: SpatialAmbientController.instance,
        builder: (context, ambient, child) {
          final themeIndex =
              ((ambient.itemId?.hashCode.abs() ?? ambient.paletteSeed) +
                  ambient.paletteSeed) %
              _ambientThemes.length;
          final colors = _ambientThemes[themeIndex];

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
                        AnimatedSwitcher(
                          duration: AppMotion.responsive(
                            context,
                            const Duration(milliseconds: 680),
                          ),
                          switchInCurve: const Cubic(0.16, 1.0, 0.3, 1.0),
                          switchOutCurve: Curves.easeInCubic,
                          child: Stack(
                            key: ValueKey(
                              'global-ambient-${ambient.itemId ?? 'default'}-${ambient.paletteSeed}',
                            ),
                            fit: StackFit.expand,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: colors,
                                    stops: const [0.0, 0.52, 1.0],
                                  ),
                                ),
                              ),
                              if (ambient.imageUri != null)
                                Transform.scale(
                                  scale: 1.14,
                                  child: Opacity(
                                    opacity: 0.52,
                                    child: PeekMediaImage(
                                      uri: ambient.imageUri,
                                      headers: ambient.imageHeaders,
                                      kind: PeekMediaImageKind.backdrop,
                                      memCacheWidth: 320,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: const Alignment(-0.38, -0.48),
                                    radius: 1.15,
                                    colors: [
                                      colors.first.withValues(alpha: 0.55),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: Alignment(0.58, 0.44),
                                    radius: 1.05,
                                    colors: [
                                      Color(0x4438BDF8),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.18),
                                  Colors.black.withValues(alpha: 0.38),
                                ],
                              ),
                            ),
                          ),
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
