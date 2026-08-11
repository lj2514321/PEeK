import 'dart:ui';

import 'package:embyplayer/src/app/theme.dart';
import 'package:flutter/material.dart';

abstract final class AppGlass {
  static const radiusSmall = 12.0;
  static const radiusMedium = 18.0;
  static const radiusLarge = 26.0;

  static BoxDecoration decoration({
    double radius = radiusMedium,
    Color? tint,
    bool elevated = false,
    bool selected = false,
  }) {
    final base =
        tint ?? (selected ? AppColors.glassSelected : AppColors.glassSurface);
    return BoxDecoration(
      color: base,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(Colors.white.withValues(alpha: 0.045), base),
          Color.alphaBlend(AppColors.indigo.withValues(alpha: 0.025), base),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: elevated ? 0.34 : 0.18),
          blurRadius: elevated ? 38 : 22,
          offset: Offset(0, elevated ? 18 : 10),
        ),
        if (selected)
          BoxShadow(
            color: AppColors.indigo.withValues(alpha: 0.16),
            blurRadius: 26,
          ),
      ],
    );
  }

  static BoxDecoration visionOSDecoration({
    double radius = radiusLarge,
    Color? tint,
    bool elevated = true,
  }) {
    final base = tint ?? Colors.black.withValues(alpha: 0.65);
    return BoxDecoration(
      color: base,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.04),
          Colors.black.withValues(alpha: 0.45),
        ],
        stops: const [0.0, 0.45, 1.0],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.22),
        width: 1.2,
      ),
      boxShadow: [
        const BoxShadow(
          color: Color(0x384A90E2),
          blurRadius: 36,
          spreadRadius: 2,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: elevated ? 0.55 : 0.3),
          blurRadius: elevated ? 42 : 24,
          offset: Offset(0, elevated ? 20 : 10),
        ),
      ],
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
    this.radius = 99,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: AppGlass.visionOSDecoration(radius: radius, elevated: true),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Padding(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// VisionOS 3D Metallic Glass Badge for quality metrics (4K, HDR, Atmos).
class VisionGlassBadge extends StatelessWidget {
  const VisionGlassBadge({
    super.key,
    required this.label,
    this.icon,
  });

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.indigo.withValues(alpha: 0.15),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppColors.spotlight),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.textPrimary,
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
    this.blur = 18,
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
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: content,
              ),
      ),
    );
  }
}

class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.canvasLift, AppColors.canvas, Color(0xFF0A0B18)],
          stops: [0, 0.52, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: -180,
            right: -120,
            child: _AmbientGlow(size: 520, color: Color(0x33767BEA)),
          ),
          const Positioned(
            bottom: -220,
            left: 40,
            child: _AmbientGlow(size: 480, color: Color(0x2458C9C5)),
          ),
          child,
        ],
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
