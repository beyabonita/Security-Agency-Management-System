import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/auth_gate.dart';
import 'package:flutter_application_1/homepage.dart';
import 'package:flutter_application_1/login.dart';
import 'package:flutter_application_1/time_logs.dart';
import 'package:flutter_application_1/supabase_config.dart';
import 'package:flutter_application_1/theme/app_theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  await appThemeController.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appThemeController,
      builder: (context, _) => MaterialApp(
        title: 'Security Agency Management System',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.light,
          useMaterial3: true,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          scaffoldBackgroundColor: AppColors.scaffold,
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            secondary: AppColors.secondary,
            surface: AppColors.surface,
            onSurface: AppColors.text,
            error: AppColors.error,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.text,
            elevation: 0,
            scrolledUnderElevation: 1,
            centerTitle: false,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
              letterSpacing: 0.3,
            ),
            iconTheme: IconThemeData(color: AppColors.text),
          ),
          cardTheme: CardThemeData(
            color: AppColors.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppColors.scaffold,
            hintStyle: const TextStyle(color: AppColors.textHint),
            labelStyle: const TextStyle(color: AppColors.textMuted),
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
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.border,
              disabledForegroundColor: AppColors.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          chipTheme: ChipThemeData(
            backgroundColor: AppColors.surface,
            selectedColor: AppColors.primary,
            disabledColor: AppColors.surfaceMuted,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            labelStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            secondaryLabelStyle: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: AppColors.primary,
            linearTrackColor: AppColors.border,
            circularTrackColor: AppColors.border,
          ),
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: AppColors.primary,
            selectionColor: Color(0x33DC2626),
            selectionHandleColor: AppColors.primary,
          ),
          listTileTheme: const ListTileThemeData(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            iconColor: AppColors.primary,
            textColor: AppColors.text,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
              fontSize: 28,
            ),
            headlineMedium: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
            titleLarge: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
            titleMedium: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            bodyLarge: TextStyle(
              color: AppColors.text,
              fontSize: 15,
              height: 1.5,
            ),
            bodyMedium: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
            labelSmall: TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.8,
            ),
          ),
          dividerTheme: const DividerThemeData(
            color: AppColors.border,
            thickness: 1,
          ),
          snackBarTheme: SnackBarThemeData(
            backgroundColor: AppColors.snackBar,
            contentTextStyle: const TextStyle(color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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
        ),
        darkTheme: _darkTheme(),
        themeMode: appThemeController.mode,
        home: const AuthGate(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const HomePage(),
          '/logs': (context) => const TimeLogsScreen(),
        },
        onUnknownRoute: (settings) =>
            MaterialPageRoute(builder: (context) => const AuthGate()),
      ),
    );
  }
}

ThemeData _darkTheme() {
  const surface = Color(0xFF21181B);
  const surfaceRaised = Color(0xFF2A1D21);
  const background = Color(0xFF151114);
  const border = Color(0xFF493337);
  const text = Color(0xFFF8ECEE);
  const muted = Color(0xFFD1B5BA);
  const hint = Color(0xFFAA8B91);

  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primaryLight,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      surface: surface,
      onSurface: text,
      error: AppColors.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: text),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceRaised,
      hintStyle: const TextStyle(color: hint),
      labelStyle: const TextStyle(color: muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: border,
        disabledForegroundColor: muted,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryLight,
        side: const BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primaryLight,
      linearTrackColor: border,
      circularTrackColor: border,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: text,
        fontWeight: FontWeight.w700,
        fontSize: 28,
      ),
      headlineMedium: TextStyle(
        color: text,
        fontWeight: FontWeight.w700,
        fontSize: 22,
      ),
      titleLarge: TextStyle(
        color: text,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
      titleMedium: TextStyle(
        color: text,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
      bodyLarge: TextStyle(color: text, fontSize: 15, height: 1.5),
      bodyMedium: TextStyle(color: muted, fontSize: 13, height: 1.4),
      labelSmall: TextStyle(
        color: hint,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
      ),
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF120C0E),
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
