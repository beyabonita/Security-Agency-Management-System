import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/admin_web_notice.dart';
import 'package:flutter_application_1/config/admin_web_config.dart';
import 'package:flutter_application_1/homepage.dart';
import 'package:flutter_application_1/services/user_profile_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Routes signed-in users:
///   admin     → AdminWebNoticeScreen  (must use web panel)
///   inspector → InspectorWebNoticeScreen (must use web panel)
///   user      → HomePage (Security Guard)
///   disabled  → _DisabledAccountScreen
class AppRoleGate extends StatelessWidget {
  const AppRoleGate({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: UserProfileService.getProfile(user.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.of(context).scaffold,
            body: GuardLoadingView(label: 'Opening your duty workspace…'),
          );
        }

        final profile = snapshot.data;

        if (profile == null) {
          return _NoticeScreen(
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.warning,
            title: 'Account not found',
            message:
                'Your account profile is missing. Please contact your administrator.',
            buttonLabel: 'Back to login',
          );
        }

        final role = profile['role']?.toString();

        if (role == 'admin') {
          return const AdminWebNoticeScreen();
        }
        if (role == 'it_admin') {
          return const ItAdminWebNoticeScreen();
        }
        if (role == 'inspector') {
          return const _InspectorWebNoticeScreen();
        }
        if (profile['active'] == false) {
          return const _DisabledAccountScreen();
        }
        return const HomePage();
      },
    );
  }
}

class _NoticeScreen extends StatelessWidget {
  const _NoticeScreen({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.buttonLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).scaffold,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(28),
              decoration: AppColors.card(context: context, radius: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: iconColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: AppColors.resolve(context, iconColor),
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.of(context).text,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.of(context).textMuted,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await Supabase.instance.client.auth.signOut();
                        if (!context.mounted) return;
                        Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/login', (r) => false);
                      },
                      child: Text(buttonLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InspectorWebNoticeScreen extends StatelessWidget {
  const _InspectorWebNoticeScreen();

  @override
  Widget build(BuildContext context) {
    return const _NoticeScreen(
      icon: Icons.manage_search_outlined,
      iconColor: AppColors.primary,
      title: 'Inspector Panel is on the Web',
      message:
          'This app is for security personnel only.\n'
          'Sign in to the Inspector web panel to view records.',
      buttonLabel: 'Sign out',
    );
  }
}

class ItAdminWebNoticeScreen extends StatelessWidget {
  const ItAdminWebNoticeScreen({super.key});

  Future<void> _openPanel() async {
    await launchUrl(
      Uri.parse(AdminWebConfig.itAdminLoginUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).scaffold,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  color: AppColors.of(context).accent,
                  size: 72,
                ),
                const SizedBox(height: 24),
                const Text(
                  'IT Admin Panel is on the Web',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This account manages system access, roles, and devices.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _openPanel,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Open IT Admin Panel'),
                ),
                TextButton(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (context.mounted) {
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/login', (route) => false);
                    }
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DisabledAccountScreen extends StatelessWidget {
  const _DisabledAccountScreen();

  @override
  Widget build(BuildContext context) {
    return const _NoticeScreen(
      icon: Icons.block_rounded,
      iconColor: AppColors.error,
      title: 'Account Disabled',
      message:
          'Your administrator has disabled this account.\n'
          'Please contact them to restore access.',
      buttonLabel: 'Back to Login',
    );
  }
}
