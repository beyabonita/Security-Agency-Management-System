import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps account connectivity separate from duty tracking and account access.
class AccountPresenceService with WidgetsBindingObserver {
  AccountPresenceService(this.client);
  final SupabaseClient client;
  StreamSubscription<AuthState>? _auth;
  Timer? _timer;
  bool _sending = false;
  bool _disposed = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _auth = client.auth.onAuthStateChange.listen((_) => _sync());
    _sync();
  }

  void _sync() {
    _timer?.cancel();
    if (_disposed || client.auth.currentSession == null) return;
    unawaited(heartbeat());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => heartbeat());
  }

  Future<void> heartbeat() async {
    if (_disposed || _sending || client.auth.currentSession == null) return;
    _sending = true;
    try {
      await client
          .rpc('touch_account_presence', params: {'p_client_kind': 'app'})
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Auth sessions determine logout; a lost connection expires presence.
    } finally {
      _sending = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
