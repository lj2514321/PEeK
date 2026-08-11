import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const canvas = Color(0xFF070810);
  static const canvasLift = Color(0xFF11152A);
  static const surfaceLow = Color(0xB3141928);
  static const surface = Color(0xCC1A2031);
  static const surfaceHigh = Color(0xE0252B3F);
  static const glassSurface = Color(0xA6171D2C);
  static const glassStrong = Color(0xDD20263A);
  static const glassSelected = Color(0xC92B3150);
  static const outline = Colors.transparent;

  static const textPrimary = Color(0xFFF4F2ED);
  static const textSecondary = Color(0xFFAEB4C0);
  static const textTertiary = Color(0xFF9299A7);

  static const spotlight = Color(0xFFFFD27D);
  static const onSpotlight = Color(0xFF19140B);
  static const indigo = Color(0xFF928BFF);
  static const cyan = Color(0xFF6EDCE8);
  static const success = Color(0xFF58C99A);
  static const error = Color(0xFFFF8585);
}

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 320);

  static const enterCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;

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
    return SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: SharedAxisTransitionType.horizontal,
      fillColor: AppColors.canvas,
      child: child,
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

    final outline = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.windows: PeekPageTransitionsBuilder()},
      ),
      focusColor: AppColors.indigo.withValues(alpha: 0.24),
      hoverColor: AppColors.textPrimary.withValues(alpha: 0.055),
      splashColor: AppColors.textPrimary.withValues(alpha: 0.08),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          fontFamily: 'Segoe UI Variable Display',
          fontFamilyFallback: const ['Microsoft YaHei UI', 'sans-serif'],
          fontSize: 48,
          height: 1.08,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.4,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontFamily: 'Segoe UI Variable Display',
          fontFamilyFallback: const ['Microsoft YaHei UI', 'sans-serif'],
          fontSize: 28,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
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
      dividerColor: AppColors.outline,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        prefixIconColor: AppColors.textTertiary,
        suffixIconColor: AppColors.textTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.14),
            width: 1.0,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.14),
            width: 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.spotlight, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          foregroundColor: AppColors.onSpotlight,
          backgroundColor: AppColors.spotlight,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textTertiary,
          shape: outline,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.glassSurface,
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1.0,
          ),
          shape: outline,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.textSecondary,
          shape: outline,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.glassSelected,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        selectedIconTheme: const IconThemeData(
          color: AppColors.spotlight,
          size: 23,
        ),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.textTertiary,
          size: 22,
        ),
        selectedLabelTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.glassSelected,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xEC0F111E),
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shadowColor: const Color(0x554A90E2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.22),
            width: 1.2,
          ),
        ),
        titleTextStyle: baseTextTheme.headlineSmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: const Color(0xF00D0E18),
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        modalBarrierColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.20),
            width: 1.2,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xEC151828),
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.20),
            width: 1.2,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.spotlight,
      ),
      cardTheme: CardThemeData(
        color: AppColors.glassSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
      ),
    );
  }
}
