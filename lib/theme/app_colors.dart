import 'package:flutter/material.dart';

/// Guard app + shared red brand (light workspace, red accents).
abstract final class AppColors {
  static const primary = Color(0xFFDC2626);
  static const primaryDark = Color(0xFFB91C1C);
  static const primaryLight = Color(0xFFEF4444);
  static const secondary = Color(0xFFF87171);

  static const scaffold = Color(0xFFFAF5F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFFEF2F2);
  static const surfaceElevated = Color(0xFFFFFCFC);
  static const border = Color(0xFFE7D5D5);
  static const text = Color(0xFF1C1917);
  static const textMuted = Color(0xFF78716C);
  static const textHint = Color(0xFFA8A29E);

  static const snackBar = Color(0xFF1C1917);
  static const error = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const errorSoft = Color(0xFFFFF1F2);
  static const successSoft = Color(0xFFECFDF5);
  static const warningSoft = Color(0xFFFFFBEB);

  /// Reading Theme establishes a dependency, so cached/routed screens repaint
  /// when the user switches modes. Brand fills remain separate from text tones.
  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;

  static Color resolve(BuildContext context, Color color) {
    final palette = of(context);
    if (color == primary || color == primaryDark || color == primaryLight) {
      return palette.accent;
    }
    if (color == error) return palette.error;
    if (color == success) return palette.success;
    if (color == warning) return palette.warning;
    if (color == text) return palette.text;
    if (color == textMuted) return palette.textMuted;
    if (color == textHint) return palette.textHint;
    if (color == surface) return palette.surface;
    if (color == surfaceMuted) return palette.surfaceMuted;
    if (color == border) return palette.border;
    return color;
  }

  static BoxDecoration card({
    required BuildContext context,
    double radius = 16,
    Color? color,
    Color? borderColor,
  }) => BoxDecoration(
    color: color ?? of(context).surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor ?? of(context).border),
    boxShadow: [
      BoxShadow(
        color: of(context).shadow,
        blurRadius: 22,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

@immutable
class AppPalette {
  const AppPalette({
    required this.scaffold,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceElevated,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textHint,
    required this.accent,
    required this.error,
    required this.success,
    required this.warning,
    required this.errorSoft,
    required this.successSoft,
    required this.warningSoft,
    required this.shadow,
  });

  final Color scaffold, surface, surfaceMuted, surfaceElevated, border;
  final Color text, textMuted, textHint, accent, error, success, warning;
  final Color errorSoft, successSoft, warningSoft, shadow;

  static const light = AppPalette(
    scaffold: AppColors.scaffold,
    surface: AppColors.surface,
    surfaceMuted: AppColors.surfaceMuted,
    surfaceElevated: AppColors.surfaceElevated,
    border: AppColors.border,
    text: AppColors.text,
    textMuted: AppColors.textMuted,
    textHint: AppColors.textMuted,
    accent: AppColors.primaryDark,
    error: Color(0xFFB91C1C),
    success: Color(0xFF15803D),
    warning: Color(0xFF92400E),
    errorSoft: AppColors.errorSoft,
    successSoft: AppColors.successSoft,
    warningSoft: AppColors.warningSoft,
    shadow: Color(0x0D451014),
  );
  static const dark = AppPalette(
    scaffold: Color(0xFF151114),
    surface: Color(0xFF21181B),
    surfaceMuted: Color(0xFF302328),
    surfaceElevated: Color(0xFF38282E),
    border: Color(0xFF60464E),
    text: Color(0xFFF8ECEE),
    textMuted: Color(0xFFD1B5BA),
    textHint: Color(0xFFBEA3AA),
    accent: Color(0xFFFDA4AF),
    error: Color(0xFFFDA4AF),
    success: Color(0xFF6EE7B7),
    warning: Color(0xFFFCD34D),
    errorSoft: Color(0xFF43212B),
    successSoft: Color(0xFF14382D),
    warningSoft: Color(0xFF3D3019),
    shadow: Color(0x33000000),
  );
}
