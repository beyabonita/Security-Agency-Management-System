import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the Guard app colour-mode choice locally and notifies the app shell.
class AppThemeController extends ChangeNotifier {
  static const _storageKey = 'sentinel_link_theme_mode';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_storageKey);
    _mode = saved == ThemeMode.dark.name ? ThemeMode.dark : ThemeMode.light;
    _applySystemUi();
  }

  Future<void> toggle() => setMode(isDark ? ThemeMode.light : ThemeMode.dark);

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    _applySystemUi();
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, mode.name);
  }

  void _applySystemUi() {
    final dark = isDark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: dark
            ? const Color(0xFF151114)
            : const Color(0xFFFAF5F5),
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
  }
}

final appThemeController = AppThemeController();
