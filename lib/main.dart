import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/auth_gate.dart';
import 'package:flutter_application_1/homepage.dart';
import 'package:flutter_application_1/login.dart';
import 'package:flutter_application_1/time_logs.dart';
import 'package:flutter_application_1/supabase_config.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/theme/app_theme_controller.dart';
import 'package:flutter_application_1/widgets/duty_tracking_scope.dart';
import 'package:flutter_application_1/services/account_presence_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  await appThemeController.load();
  AccountPresenceService(Supabase.instance.client).start();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DutyTrackingScope(
      child: AnimatedBuilder(
        animation: appThemeController,
        builder: (context, _) => MaterialApp(
          title: 'Security Agency Management System',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
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
      ),
    );
  }
}
