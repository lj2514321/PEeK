import 'dart:io';

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const canvas = Color(0xFF0A0F1D);
  static const canvasLift = Color(0xFF16223C);
  static const surfaceLow = Color(0x1FFFFFFF);
  static const surface = Color(0x29FFFFFF);
  static const surfaceHigh = Color(0x38FFFFFF);
  static const glassSurface = Color(0x24FFFFFF);
  static const glassStrong = Color(0x36FFFFFF);
  static const glassSelected = Color(0x47FFFFFF);
  static const outline = Color(0x47FFFFFF);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xD9FFFFFF);
  static const textTertiary = Color(0xA6FFFFFF);

  static const spotlight = Color(0xFFFFFFFF);
  static const spotlightLight = Color(0xFFE2E8F0);
  static const onSpotlight = Color(0xFF0A0C14);
  static const indigo = Color(0xFF7DD3FC);
  static const cyan = Color(0xFF38BDF8);
  static const cyanLight = Color(0xFFBAE6FD);
  static const success = Color(0xFF34D399);
  static const error = Color(0xFFFB7185);
}

/// 全局统一圆角常量（窗口容器与所有组件统一引用）
const double kAppCornerRadius = 28.0;

abstract final class AppRadius {
  /// 全局统一圆角数值常量
  static const double value = kAppCornerRadius;

  /// 全局统一 Radius 常量
  static const Radius circular = Radius.circular(value);

  /// 全局统一 BorderRadius 常量
  static const BorderRadius borderRadius = BorderRadius.all(circular);

  /// 全局统一 RoundedRectangleBorder 形状常量
  static const RoundedRectangleBorder shape = RoundedRectangleBorder(
    borderRadius: borderRadius,
  );
}

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 320);

  static const enterCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;

  static final bool isTest = Platform.environment.containsKey('FLUTTER_TEST');

  static Duration responsive(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}

class PeekPageTransitionsBuilder extends PageTransitionsBuilder {
  const PeekPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (context != null && MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final enterCurved = CurvedAnimation(
      parent: animation,
      curve: const Cubic(0.22, 0.84, 0.26, 1.0),
      reverseCurve: Curves.easeInCubic,
    );
    final fadeCurved = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.72, curve: Curves.easeOutCubic),
      reverseCurve: Curves.easeInQuad,
    );
    final exitCurved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Cubic(0.24, 0.08, 0.22, 1.0),
      reverseCurve: const Cubic(0.22, 0.84, 0.26, 1.0),
    );
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 0.935).animate(exitCurved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 0.048),
          end: Offset.zero,
        ).animate(enterCurved),
        child: FadeTransition(
          opacity: fadeCurved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.925, end: 1.0).animate(enterCurved),
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    );
  }
}

abstract final class AppTheme {
  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.spotlight,
      onPrimary: AppColors.onSpotlight,
      secondary: AppColors.indigo,
      onSecondary: AppColors.textPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      onError: AppColors.canvas,
      outline: AppColors.outline,
    );

    final baseTextTheme =
        Typography.material2021(platform: TargetPlatform.windows).white.apply(
          fontFamily: 'Segoe UI Variable Text',
          fontFamilyFallback: const ['Microsoft YaHei UI', 'sans-serif'],
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        );

    const unifiedShape = AppRadius.shape;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: PeekPageTransitionsBuilder(),
          TargetPlatform.android: PeekPageTransitionsBuilder(),
          TargetPlatform.iOS: PeekPageTransitionsBuilder(),
          TargetPlatform.macOS: PeekPageTransitionsBuilder(),
          TargetPlatform.linux: PeekPageTransitionsBuilder(),
        },
      ),
      focusColor: Colors.white.withValues(alpha: 0.22),
      hoverColor: Colors.white.withValues(alpha: 0.08),
      splashColor: Colors.white.withValues(alpha: 0.12),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          fontFamily: 'Segoe UI Variable Display',
          fontFamilyFallback: const ['Microsoft YaHei UI', 'sans-serif'],
          fontSize: 48,
          height: 1.08,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.4,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontFamily: 'Segoe UI Variable Display',
          fontFamilyFallback: const ['Microsoft YaHei UI', 'sans-serif'],
          fontSize: 28,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.58,
          color: AppColors.textSecondary,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontFamily: 'Cascadia Mono',
          fontFamilyFallback: const ['Consolas', 'monospace'],
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.15,
          color: AppColors.textTertiary,
        ),
      ),
      dividerColor: Colors.white.withValues(alpha: 0.18),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.12),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderRadius,
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1.1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadius,
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1.1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadius,
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.75),
            width: 1.6,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadius,
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          foregroundColor: AppColors.onSpotlight,
          backgroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.18),
          disabledForegroundColor: AppColors.textTertiary,
          shape: unifiedShape,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          foregroundColor: AppColors.textPrimary,
          backgroundColor: Colors.white.withValues(alpha: 0.14),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.34),
            width: 1.1,
          ),
          shape: unifiedShape,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.textSecondary,
          shape: unifiedShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: AppColors.textPrimary,
          shape: unifiedShape,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        selectedColor: Colors.white.withValues(alpha: 0.30),
        disabledColor: Colors.white.withValues(alpha: 0.06),
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        checkmarkColor: Colors.white,
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.28),
          width: 1.0,
        ),
        shape: unifiedShape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xE6162038),
        surfaceTintColor: Colors.transparent,
        elevation: 20,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadius,
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.32),
            width: 1.2,
          ),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.glassSelected,
        indicatorShape: AppRadius.shape,
        selectedIconTheme: IconThemeData(color: Colors.white, size: 23),
        unselectedIconTheme: IconThemeData(
          color: AppColors.textTertiary,
          size: 22,
        ),
        selectedLabelTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.glassSelected,
        indicatorShape: AppRadius.shape,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xE6151F36),
        surfaceTintColor: Colors.transparent,
        elevation: 28,
        shadowColor: Colors.black.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadius,
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.34),
            width: 1.2,
          ),
        ),
        titleTextStyle: baseTextTheme.headlineSmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xEB141E34),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBarrierColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: AppRadius.circular),
          side: BorderSide.none,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 360,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        backgroundColor: const Color(0xDE283347),
        contentTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        elevation: 20,
        showCloseIcon: true,
        closeIconColor: AppColors.textSecondary,
        actionTextColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadius,
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.42),
            width: 1.2,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        decoration: BoxDecoration(
          color: const Color(0xE0283347),
          borderRadius: AppRadius.borderRadius,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.36),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: AppColors.glassSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadius,
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1.1,
          ),
        ),
      ),
    );
  }
}
