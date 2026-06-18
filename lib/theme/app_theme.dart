import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

/// Every color the app actually uses, with a light and dark variant.
/// This is the single source of truth for dark-mode-aware colors — screens
/// read `context.colors.X` (see the AppColorsX extension below) instead of
/// the static AppColors.X constants, so they automatically repaint on
/// theme toggle. Brand/semantic colors (primary, accent, error, warning,
/// status/trust/rating colors) get a slightly brighter dark variant so they
/// keep adequate contrast against their own dark-mode "Surface" pairing;
/// pure neutrals (background/surface/borders/text) invert.
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color primary;
  final Color primaryDark;
  final Color primarySurface;
  final Color accent;
  final Color accentSurface;
  final Color error;
  final Color errorSurface;
  final Color warning;
  final Color warningSurface;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color border;
  final Color borderLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInverse;
  final Color bubbleSent;
  final Color bubbleReceived;
  final Color statusRequested;
  final Color statusMatched;
  final Color statusInChat;
  final Color statusEscrowLocked;
  final Color statusInProgress;
  final Color statusSubmitted;
  final Color statusCompleted;
  final Color statusDisputed;
  final Color statusResolved;
  final Color ratingGold;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color risingBadge;
  final Color risingBadgeSurface;
  final Color trustElite;
  final Color trustEliteSurface;
  final Color trustTrusted;
  final Color trustTrustedSurface;

  const AppColorsExtension({
    required this.primary,
    required this.primaryDark,
    required this.primarySurface,
    required this.accent,
    required this.accentSurface,
    required this.error,
    required this.errorSurface,
    required this.warning,
    required this.warningSurface,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.border,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.bubbleSent,
    required this.bubbleReceived,
    required this.statusRequested,
    required this.statusMatched,
    required this.statusInChat,
    required this.statusEscrowLocked,
    required this.statusInProgress,
    required this.statusSubmitted,
    required this.statusCompleted,
    required this.statusDisputed,
    required this.statusResolved,
    required this.ratingGold,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.risingBadge,
    required this.risingBadgeSurface,
    required this.trustElite,
    required this.trustEliteSurface,
    required this.trustTrusted,
    required this.trustTrustedSurface,
  });

  static const light = AppColorsExtension(
    primary: AppColors.primary,
    primaryDark: AppColors.primaryDark,
    primarySurface: AppColors.primarySurface,
    accent: AppColors.accent,
    accentSurface: AppColors.accentSurface,
    error: AppColors.error,
    errorSurface: AppColors.errorSurface,
    warning: AppColors.warning,
    warningSurface: AppColors.warningSurface,
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceVariant: AppColors.surfaceVariant,
    border: AppColors.border,
    borderLight: AppColors.borderLight,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    textInverse: AppColors.textInverse,
    bubbleSent: AppColors.bubbleSent,
    bubbleReceived: AppColors.bubbleReceived,
    statusRequested: AppColors.statusRequested,
    statusMatched: AppColors.statusMatched,
    statusInChat: AppColors.statusInChat,
    statusEscrowLocked: AppColors.statusEscrowLocked,
    statusInProgress: AppColors.statusInProgress,
    statusSubmitted: AppColors.statusSubmitted,
    statusCompleted: AppColors.statusCompleted,
    statusDisputed: AppColors.statusDisputed,
    statusResolved: AppColors.statusResolved,
    ratingGold: AppColors.ratingGold,
    shimmerBase: AppColors.shimmerBase,
    shimmerHighlight: AppColors.shimmerHighlight,
    risingBadge: AppColors.risingBadge,
    risingBadgeSurface: AppColors.risingBadgeSurface,
    trustElite: AppColors.trustElite,
    trustEliteSurface: AppColors.trustEliteSurface,
    trustTrusted: AppColors.trustTrusted,
    trustTrustedSurface: AppColors.trustTrustedSurface,
  );

  static const dark = AppColorsExtension(
    primary: Color(0xFF3B82F6),
    primaryDark: Color(0xFF60A5FA),
    primarySurface: Color(0xFF1E3A8A),
    accent: Color(0xFF34D399),
    accentSurface: Color(0xFF065F46),
    error: Color(0xFFF87171),
    errorSurface: Color(0xFF7F1D1D),
    warning: Color(0xFFFBBF24),
    warningSurface: Color(0xFF78350F),
    background: Color(0xFF111827),
    surface: Color(0xFF1F2937),
    surfaceVariant: Color(0xFF374151),
    border: Color(0xFF4B5563),
    borderLight: Color(0xFF374151),
    textPrimary: Color(0xFFF3F4F6),
    textSecondary: Color(0xFFD1D5DB),
    textTertiary: Color(0xFF9CA3AF),
    textInverse: Color(0xFF0B1220),
    bubbleSent: Color(0xFF3B82F6),
    bubbleReceived: Color(0xFF374151),
    statusRequested: Color(0xFF9CA3AF),
    statusMatched: Color(0xFFC4B5FD),
    statusInChat: Color(0xFF60A5FA),
    statusEscrowLocked: Color(0xFF34D399),
    statusInProgress: Color(0xFFFBBF24),
    statusSubmitted: Color(0xFF60A5FA),
    statusCompleted: Color(0xFF34D399),
    statusDisputed: Color(0xFFF87171),
    statusResolved: Color(0xFF9CA3AF),
    ratingGold: Color(0xFFFBBF24),
    shimmerBase: Color(0xFF374151),
    shimmerHighlight: Color(0xFF4B5563),
    risingBadge: Color(0xFFC4B5FD),
    risingBadgeSurface: Color(0xFF4C1D95),
    trustElite: Color(0xFFFBBF24),
    trustEliteSurface: Color(0xFF78350F),
    trustTrusted: Color(0xFF60A5FA),
    trustTrustedSurface: Color(0xFF1E3A8A),
  );

  @override
  AppColorsExtension copyWith() => this;

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    Color m(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppColorsExtension(
      primary: m(primary, other.primary),
      primaryDark: m(primaryDark, other.primaryDark),
      primarySurface: m(primarySurface, other.primarySurface),
      accent: m(accent, other.accent),
      accentSurface: m(accentSurface, other.accentSurface),
      error: m(error, other.error),
      errorSurface: m(errorSurface, other.errorSurface),
      warning: m(warning, other.warning),
      warningSurface: m(warningSurface, other.warningSurface),
      background: m(background, other.background),
      surface: m(surface, other.surface),
      surfaceVariant: m(surfaceVariant, other.surfaceVariant),
      border: m(border, other.border),
      borderLight: m(borderLight, other.borderLight),
      textPrimary: m(textPrimary, other.textPrimary),
      textSecondary: m(textSecondary, other.textSecondary),
      textTertiary: m(textTertiary, other.textTertiary),
      textInverse: m(textInverse, other.textInverse),
      bubbleSent: m(bubbleSent, other.bubbleSent),
      bubbleReceived: m(bubbleReceived, other.bubbleReceived),
      statusRequested: m(statusRequested, other.statusRequested),
      statusMatched: m(statusMatched, other.statusMatched),
      statusInChat: m(statusInChat, other.statusInChat),
      statusEscrowLocked: m(statusEscrowLocked, other.statusEscrowLocked),
      statusInProgress: m(statusInProgress, other.statusInProgress),
      statusSubmitted: m(statusSubmitted, other.statusSubmitted),
      statusCompleted: m(statusCompleted, other.statusCompleted),
      statusDisputed: m(statusDisputed, other.statusDisputed),
      statusResolved: m(statusResolved, other.statusResolved),
      ratingGold: m(ratingGold, other.ratingGold),
      shimmerBase: m(shimmerBase, other.shimmerBase),
      shimmerHighlight: m(shimmerHighlight, other.shimmerHighlight),
      risingBadge: m(risingBadge, other.risingBadge),
      risingBadgeSurface: m(risingBadgeSurface, other.risingBadgeSurface),
      trustElite: m(trustElite, other.trustElite),
      trustEliteSurface: m(trustEliteSurface, other.trustEliteSurface),
      trustTrusted: m(trustTrusted, other.trustTrusted),
      trustTrustedSurface: m(trustTrustedSurface, other.trustTrustedSurface),
    );
  }
}

/// Ergonomic access: `context.colors.textPrimary` instead of
/// `Theme.of(context).extension<AppColorsExtension>()!.textPrimary`.
extension AppColorsX on BuildContext {
  AppColorsExtension get colors => Theme.of(this).extension<AppColorsExtension>()!;
}

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        extensions: const [AppColorsExtension.light],
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.primary,
          onPrimary: AppColors.textInverse,
          primaryContainer: AppColors.primarySurface,
          onPrimaryContainer: AppColors.primaryDark,
          secondary: AppColors.accent,
          onSecondary: AppColors.textInverse,
          secondaryContainer: AppColors.accentSurface,
          onSecondaryContainer: Color(0xFF065F46),
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          surfaceContainerHighest: AppColors.surfaceVariant,
          onSurfaceVariant: AppColors.textSecondary,
          error: AppColors.error,
          onError: AppColors.textInverse,
          errorContainer: AppColors.errorSurface,
          onErrorContainer: Color(0xFF7F1D1D),
          outline: AppColors.border,
          outlineVariant: AppColors.borderLight,
          shadow: Color(0x1A000000),
        ),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 1,
          shadowColor: Color(0x1A000000),
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textInverse,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error, width: 1.5),
          ),
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
          hintStyle: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textTertiary,
            fontSize: 14,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.borderLight),
          ),
          margin: EdgeInsets.zero,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfaceVariant,
          selectedColor: AppColors.primarySurface,
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textTertiary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.borderLight,
          thickness: 1,
          space: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.textPrimary,
          contentTextStyle: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textInverse,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.2,
          ),
          headlineSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.1,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          titleSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
          ),
          bodySmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          labelLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          labelSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
          ),
        ),
      );

  /// Mirrors light's structure component-for-component. Most screens in
  /// this app style themselves directly off AppColors constants rather
  /// than Theme.of(context), so this theme drives Flutter's own built-in
  /// widgets (default Scaffold/AppBar/SnackBar/inputs/buttons not given an
  /// explicit color) correctly, but won't repaint screens that hardcode
  /// AppColors.* — see the theme system audit note for what that means
  /// in practice.
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        extensions: const [AppColorsExtension.dark],
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF3B82F6),
          onPrimary: Color(0xFF0B1220),
          primaryContainer: Color(0xFF1E3A8A),
          onPrimaryContainer: Color(0xFFDBEAFE),
          secondary: Color(0xFF34D399),
          onSecondary: Color(0xFF0B1220),
          secondaryContainer: Color(0xFF065F46),
          onSecondaryContainer: Color(0xFFD1FAE5),
          surface: Color(0xFF1F2937),
          onSurface: Color(0xFFF3F4F6),
          surfaceContainerHighest: Color(0xFF374151),
          onSurfaceVariant: Color(0xFFD1D5DB),
          error: Color(0xFFF87171),
          onError: Color(0xFF450A0A),
          errorContainer: Color(0xFF7F1D1D),
          onErrorContainer: Color(0xFFFEE2E2),
          outline: Color(0xFF4B5563),
          outlineVariant: Color(0xFF374151),
          shadow: Color(0x33000000),
        ),
        scaffoldBackgroundColor: const Color(0xFF111827),
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F2937),
          foregroundColor: Color(0xFFF3F4F6),
          elevation: 0,
          scrolledUnderElevation: 1,
          shadowColor: Color(0x33000000),
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF3F4F6),
            letterSpacing: -0.3,
          ),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: const Color(0xFF0B1220),
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF3B82F6),
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF3B82F6),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1F2937),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4B5563)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4B5563)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFF87171)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFF87171), width: 1.5),
          ),
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFFD1D5DB),
            fontSize: 14,
          ),
          hintStyle: const TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFF9CA3AF),
            fontSize: 14,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1F2937),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF374151)),
          ),
          margin: EdgeInsets.zero,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF374151),
          selectedColor: const Color(0xFF1E3A8A),
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFFF3F4F6),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1F2937),
          selectedItemColor: Color(0xFF3B82F6),
          unselectedItemColor: Color(0xFF9CA3AF),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF374151),
          thickness: 1,
          space: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF374151),
          contentTextStyle: const TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFFF3F4F6),
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF3F4F6),
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF3F4F6),
            letterSpacing: -0.3,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF3F4F6),
            letterSpacing: -0.3,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF3F4F6),
            letterSpacing: -0.2,
          ),
          headlineSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF3F4F6),
            letterSpacing: -0.1,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF3F4F6),
          ),
          titleMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFFF3F4F6),
          ),
          titleSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFFD1D5DB),
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Color(0xFFF3F4F6),
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFFF3F4F6),
          ),
          bodySmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: Color(0xFFD1D5DB),
          ),
          labelLarge: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF3F4F6),
          ),
          labelSmall: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFF9CA3AF),
          ),
        ),
      );
}
