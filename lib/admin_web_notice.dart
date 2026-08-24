import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/config/admin_web_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shown when an admin is signed in on the mobile/desktop app.
/// Admin management runs in the web panel, not in this app.
class AdminWebNoticeScreen extends StatelessWidget {
  const AdminWebNoticeScreen({super.key});

  Future<void> _openWebAdmin() async {
    if (AdminWebConfig.adminLoginUrl.isEmpty) {
      debugPrint('Admin web panel has not been configured yet.');
      return;
    }
    final uri = Uri.parse(AdminWebConfig.adminLoginUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not open admin URL: $uri');
    }
  }

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              const Text(
                'HR / Operations panel is on the web',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                kIsWeb
                    ? 'Open the HR / Operations pages in this browser to manage personnel, '
                          'locations, schedules, and reports.'
                    : 'This app is for security personnel only. '
                          'Sign in to the web admin panel to manage the system.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700], height: 1.4),
              ),
              const SizedBox(height: 32),
              if (kIsWeb && AdminWebConfig.adminLoginUrl.isNotEmpty)
                FilledButton.icon(
                  onPressed: () {
                    // Same origin when running `flutter run -d chrome`
                    launchUrl(
                      Uri.parse('/staff/login.html'),
                      webOnlyWindowName: '_self',
                    );
                  },
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Go to Staff Login'),
                )
              else if (AdminWebConfig.adminLoginUrl.isNotEmpty)
                FilledButton.icon(
                  onPressed: _openWebAdmin,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Open HR / Operations Web Panel'),
                )
              else
                const Text(
                  'The Supabase admin panel has not been deployed yet.',
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _signOut(context),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
