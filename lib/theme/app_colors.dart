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

  static BoxDecoration card({
    double radius = 16,
    Color color = surface,
    Color borderColor = border,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor),
    boxShadow: const [
      BoxShadow(color: Color(0x0D451014), blurRadius: 22, offset: Offset(0, 8)),
      BoxShadow(color: Color(0x08FFFFFF), blurRadius: 2, offset: Offset(0, -1)),
    ],
  );
}
