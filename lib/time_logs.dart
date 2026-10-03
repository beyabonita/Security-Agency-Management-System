import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/guard_dtr.dart';
import 'services/guard_dtr_service.dart';
import 'services/guard_dtr_pdf.dart';
import 'theme/app_colors.dart';
import 'widgets/guard_ui.dart';
import 'widgets/guard_dtr_sheet.dart';

class TimeLogsScreen extends StatefulWidget {
  const TimeLogsScreen({super.key, this.loadReport, this.saveReport});
  final Future<GuardDtr> Function(GuardDtrPeriod)? loadReport;
  final Future<bool> Function(GuardDtr)? saveReport;
  @override
  State<TimeLogsScreen> createState() => _TimeLogsScreenState();
}

class _TimeLogsScreenState extends State<TimeLogsScreen>
    with WidgetsBindingObserver {
  late GuardDtrPeriod _period;
  GuardDtr? _report;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  int _request = 0;
  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _auth;
  Timer? _refresh;
  final _tableScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = GuardDtr.philippineTime(DateTime.now());
    _period = GuardDtrPeriod(now.year, now.month, now.day > 15);
    if (widget.loadReport == null) {
      final client = Supabase.instance.client;
      final id = client.auth.currentUser?.id;
      if (id != null) {
        _channel = client
            .channel('guard-dtr-$id-${identityHashCode(this)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'attendance_sessions',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: id,
              ),
              callback: (_) {
                _refresh?.cancel();
                _refresh = Timer(const Duration(milliseconds: 300), _load);
              },
            )
            .subscribe();
      }
      _auth = client.auth.onAuthStateChange.listen((event) {
        if (event.session?.user.id != id && mounted) {
          _request++;
          setState(() {
            _report = null;
            _loading = false;
            _error = 'Please reopen your DTR after signing in.';
          });
        }
      });
    }
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader =
          widget.loadReport ?? GuardDtrService(Supabase.instance.client).load;
      final report = await loader(_period).timeout(const Duration(seconds: 20));
      if (!mounted || request != _request) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _error =
            'Could not load your DTR. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  void _select(GuardDtrPeriod period) {
    setState(() {
      _period = period;
      _report = null;
    });
    _load();
  }

  void _moveMonth(int offset) {
    final date = DateTime(_period.year, _period.month + offset);
    _select(GuardDtrPeriod(date.year, date.month, _period.secondHalf));
  }

  Future<void> _save() async {
    final report = _report;
    if (report == null || _saving || _loading || _error != null) return;
    setState(() => _saving = true);
    try {
      final saved = await (widget.saveReport ?? GuardDtrPdf.save)(report);
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('DTR saved.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the PDF. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    _auth?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    _tableScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).scaffold,
    body: SafeArea(
      child: Column(
        children: [
          GuardPageTopBar(
            title: 'My DTR',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => _moveMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          _period.monthLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => _moveMonth(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<bool>(
                    key: ValueKey(_period.secondHalf),
                    initialValue: _period.secondHalf,
                    decoration: const InputDecoration(labelText: 'DTR cut-off'),
                    items: const [
                      DropdownMenuItem(value: false, child: Text('1st–15th')),
                      DropdownMenuItem(
                        value: true,
                        child: Text('16th–end of month'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _select(
                          GuardDtrPeriod(_period.year, _period.month, value),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              _report == null ||
                                  _loading ||
                                  _saving ||
                                  _error != null
                              ? null
                              : _save,
                          icon: const Icon(Icons.download_outlined),
                          label: Text(_saving ? 'Saving PDF…' : 'Download DTR'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh DTR',
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(_error!),
                    ),
                  const SizedBox(height: 12),
                  if (_report != null)
                    GuardDtrSheet(report: _report!, tableScroll: _tableScroll),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
