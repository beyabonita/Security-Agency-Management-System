import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/attendance_session.dart';

/// Connection and GPS activity must not reset an already confirmed punch state.
class AttendanceStateController extends ChangeNotifier {
  AttendanceStateController({
    required this.loadSession,
    this.requestTimeout = const Duration(seconds: 15),
  });

  final Future<AttendanceSession?> Function() loadSession;
  final Duration requestTimeout;
  AttendanceSession? session;
  AttendanceSession? latestSession;
  bool hasConfirmedSession = false;
  bool refreshing = false;
  Object? error;
  bool _disposed = false;
  Future<void>? _pending;
  int _revision = 0;

  bool get initialLoading => !hasConfirmedSession && refreshing;

  void accept(AttendanceSession? value) {
    if (_disposed) return;
    ++_revision;
    latestSession = value;
    session = value?.isOpen == true ? value : null;
    hasConfirmedSession = true;
    error = null;
    notifyListeners();
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_pending != null) return _pending!;
    final operation = _load();
    _pending = operation;
    return operation.whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
    });
  }

  Future<void> _load() async {
    final revision = _revision;
    refreshing = true;
    notifyListeners();
    try {
      final value = await loadSession().timeout(requestTimeout);
      if (!_disposed && revision == _revision) accept(value);
    } catch (failure) {
      if (!_disposed && revision == _revision) error = failure;
    } finally {
      if (!_disposed) {
        refreshing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
