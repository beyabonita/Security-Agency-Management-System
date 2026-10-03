import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'app_colors.dart';

/// Both modes share component geometry, spacing and state handling.
abstract final class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final p = dark ? AppPalette.dark : AppPalette.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: p.accent,
          onPrimary: dark ? p.scaffold : Colors.white,
          primaryContainer: p.surfaceMuted,
          onPrimaryContainer: p.text,
          secondary: p.accent,
          onSecondary: dark ? p.scaffold : Colors.white,
          surface: p.surface,
          onSurface: p.text,
          onSurfaceVariant: p.textMuted,
          surfaceContainerHighest: p.surfaceMuted,
          outline: p.border,
          outlineVariant: p.border,
          error: p.error,
          onError: dark ? p.scaffold : Colors.white,
          errorContainer: p.errorSoft,
          onErrorContainer: p.error,
        );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: p.surfaceMuted,
      disabledForegroundColor: p.textHint,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      shape: buttonShape,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.scaffold,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      disabledColor: p.textHint,
      dividerColor: p.border,
      iconTheme: IconThemeData(color: p.textMuted),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: p.text,
          letterSpacing: .3,
        ),
        iconTheme: IconThemeData(color: p.text),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMuted,
        hintStyle: TextStyle(color: p.textHint),
        labelStyle: TextStyle(color: p.textMuted),
        helperStyle: TextStyle(color: p.textMuted),
        errorStyle: TextStyle(color: p.error),
        prefixIconColor: p.textMuted,
        suffixIconColor: p.textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.accent,
          disabledForegroundColor: p.textHint,
          side: BorderSide(color: p.border),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.accent),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.text,
          minimumSize: const Size(44, 44),
          shape: buttonShape,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceMuted,
        selectedColor: AppColors.primary,
        disabledColor: p.surfaceMuted,
        checkmarkColor: Colors.white,
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(
          color: p.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.border,
        circularTrackColor: p.border,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: .25),
        selectionHandleColor: p.accent,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: p.accent,
        textColor: p.text,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceElevated,
        textStyle: TextStyle(color: p.text),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.surfaceMuted,
        headerForegroundColor: p.text,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.surface,
        hourMinuteColor: p.surfaceMuted,
        hourMinuteTextColor: p.text,
        dayPeriodTextColor: p.text,
        dayPeriodColor: p.surfaceMuted,
        dialBackgroundColor: p.surfaceMuted,
        dialTextColor: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.onPrimary : p.text,
        ),
        dialHandColor: p.accent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.border),
        ),
        textStyle: TextStyle(color: p.text),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: p.text,
          fontWeight: FontWeight.w700,
          fontSize: 28,
        ),
        headlineMedium: TextStyle(
          color: p.text,
          fontWeight: FontWeight.w700,
          fontSize: 22,
        ),
        titleLarge: TextStyle(
          color: p.text,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        titleMedium: TextStyle(
          color: p.text,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        bodyLarge: TextStyle(color: p.text, fontSize: 15, height: 1.5),
        bodyMedium: TextStyle(color: p.textMuted, fontSize: 13, height: 1.4),
        bodySmall: TextStyle(color: p.textMuted, fontSize: 12),
        labelSmall: TextStyle(
          color: p.textHint,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: .8,
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? p.surfaceElevated : AppColors.snackBar,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
