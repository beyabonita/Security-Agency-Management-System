import 'package:flutter/material.dart';
import 'package:flutter_application_1/login.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/theme/app_theme_controller.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

Widget app(Widget child) => AnimatedBuilder(
  animation: appThemeController,
  builder: (context, _) => MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: appThemeController.mode,
    home: child,
  ),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await appThemeController.setMode(ThemeMode.light);
  });

  test(
    'dark palette keeps body and status text readable on all dark surfaces',
    () {
      const p = AppPalette.dark;
      for (final text in [
        p.text,
        p.textMuted,
        p.textHint,
        p.accent,
        p.error,
        p.success,
        p.warning,
      ]) {
        for (final surface in [
          p.scaffold,
          p.surface,
          p.surfaceMuted,
          p.surfaceElevated,
        ]) {
          expect(contrast(text, surface), greaterThanOrEqualTo(4.5));
        }
      }
      expect(
        contrast(Colors.white, AppColors.primary),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  test('theme preference is restored by a new controller', () async {
    final first = AppThemeController();
    await first.setMode(ThemeMode.dark);
    final second = AppThemeController();
    await second.load();
    expect(second.mode, ThemeMode.dark);
    await second.toggle();
    final third = AppThemeController();
    await third.load();
    expect(third.mode, ThemeMode.light);
    first.dispose();
    second.dispose();
    third.dispose();
  });

  testWidgets(
    'actual Guard login toggles without losing input and validates in dark mode',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(const LoginScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'qa.guard');
      await tester.tap(find.byTooltip('Switch to dark mode'));
      await tester.pumpAndSettle();
      expect(appThemeController.mode, ThemeMode.dark);
      expect(find.text('qa.guard'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.style!.color, AppPalette.dark.text);
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GuardSurfaceCard),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (container.decoration! as BoxDecoration).color,
        AppPalette.dark.surface,
      );
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter your username and password.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Switch to light mode'));
      await tester.tap(find.byTooltip('Switch to light mode'));
      await tester.pumpAndSettle();
      expect(appThemeController.mode, ThemeMode.light);
      expect(find.text('qa.guard'), findsOneWidget);
    },
  );

  testWidgets(
    'status banners, empty states and navigation repaint when the theme changes',
    (tester) async {
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Column(
              children: [
                GuardPageTopBar(title: 'Duty requests', onBack: () {}),
                const GuardStatusBanner(
                  message: 'Request approved',
                  title: 'Status',
                  color: AppColors.success,
                  icon: Icons.check,
                ),
                const Expanded(
                  child: GuardEmptyState(
                    icon: Icons.calendar_month,
                    title: 'No requests',
                    message: 'Your duty requests will appear here.',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await appThemeController.setMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Icon>(find.byIcon(Icons.check)).color,
        AppPalette.dark.success,
      );
      expect(
        tester
            .widget<Icon>(find.byIcon(Icons.arrow_back_ios_new_rounded))
            .color,
        AppPalette.dark.text,
      );
      final title = tester.widget<Text>(find.text('No requests'));
      expect(title.style!.color, AppPalette.dark.text);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmation dialog uses a dark surface with contrasting actions',
    (tester) async {
      await appThemeController.setMode(ThemeMode.dark);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showGuardConfirmation(
                  context,
                  title: 'Discard report?',
                  message: 'Unsaved details will be discarded.',
                  destructive: true,
                ),
                child: const Text('Open confirmation'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open confirmation'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AlertDialog));
      expect(
        Theme.of(context).dialogTheme.backgroundColor,
        AppPalette.dark.surface,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.warning_amber_rounded)).color,
        AppPalette.dark.error,
      );
      final style = Theme.of(context).filledButtonTheme.style!;
      expect(style.backgroundColor!.resolve({}), AppColors.primary);
      expect(style.foregroundColor!.resolve({}), Colors.white);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
