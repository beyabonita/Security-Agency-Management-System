import 'package:flutter/material.dart';
import 'package:flutter_application_1/app_role_gate.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/services/device_service.dart';
import 'package:flutter_application_1/services/user_profile_service.dart';
import 'package:flutter_application_1/utils/auth_username.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(
        () => _errorMessage = 'Please enter your username and password.',
      );
      return;
    }
    final usernameError = username.contains('@')
        ? null
        : validateUsername(username);
    if (usernameError != null) {
      setState(() => _errorMessage = usernameError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final cred = await Supabase.instance.client.auth.signInWithPassword(
        email: resolveAuthEmail(username),
        password: password,
      );
      final uid = cred.user!.id;

      final loginError = await UserProfileService.validateGuardLogin(uid);
      if (loginError == 'admin') {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage =
              'HR and Inspector accounts use the Staff web panel at /staff/login.html';
        });
        return;
      }
      if (loginError == 'it_admin') {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage =
              'IT Admin accounts use the private system-access web address.';
        });
        return;
      }
      if (loginError != null) {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = loginError;
        });
        return;
      }

      try {
        final deviceId = await DeviceService.getOrCreateDeviceId();
        await UserProfileService.registerDeviceIfNeeded(uid, deviceId);
      } catch (e) {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
        return;
      }

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const AppRoleGate()));
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = switch (e.code) {
          'invalid_credentials' => 'Incorrect username or password.',
          'email_not_confirmed' => 'Confirm your email before signing in.',
          'over_request_rate_limit' =>
            'Too many attempts. Please try again later.',
          _ => e.message,
        };
      });
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: GuardAmbientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Hero(
                        tag: 'sentinel-link-mark',
                        child: const SentinelBrandMark(
                          size: 76,
                          semanticLabel: 'Sentinel Link logo',
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Sentinel Link',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Guard mobile access',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 32),
                      GuardSurfaceCard(
                        padding: const EdgeInsets.all(24),
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildLabel('USERNAME'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _usernameController,
                                focusNode: _usernameFocus,
                                autofillHints: const [AutofillHints.username],
                                keyboardType: TextInputType.text,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                style: const TextStyle(color: AppColors.text),
                                decoration: const InputDecoration(
                                  hintText: 'juan.delacruz',
                                  prefixIcon: Icon(
                                    Icons.person_outline_rounded,
                                    color: AppColors.textHint,
                                    size: 20,
                                  ),
                                ),
                                onSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                              ),
                              const SizedBox(height: 16),
                              _buildLabel('PASSWORD'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                autofillHints: const [AutofillHints.password],
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                style: const TextStyle(color: AppColors.text),
                                decoration: InputDecoration(
                                  hintText: '••••••••',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                    color: AppColors.textHint,
                                    size: 20,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: AppColors.textHint,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) => _login(),
                              ),
                              if (_errorMessage.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Semantics(
                                  liveRegion: true,
                                  child: GuardStatusBanner(
                                    message: _errorMessage,
                                    color: AppColors.error,
                                    icon: Icons.error_outline_rounded,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  child: GuardBusyLabel(
                                    busy: _isLoading,
                                    label: 'Sign in',
                                    busyLabel: 'Signing in…',
                                    icon: Icons.login_rounded,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Need an account? Ask your administrator.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}
