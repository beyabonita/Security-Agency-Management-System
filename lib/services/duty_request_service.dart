import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/models/request_letter.dart';
import 'package:flutter_application_1/models/accomplishment_photo.dart';

class DutyRequestData {
  const DutyRequestData({required this.schedules, required this.requests});
  final List<Map<String, dynamic>> schedules;
  final List<Map<String, dynamic>> requests;
}

abstract interface class DutyRequestGateway {
  Future<DutyRequestData> load();
  Future<List<Map<String, dynamic>>> swapOptions(String scheduleId);
  Future<void> submit({
    required String scheduleId,
    required String reason,
    required String requestType,
    required RequestLetter letter,
    String? targetScheduleId,
  });
  Future<void> discard(RequestLetter letter);
  Future<void> respondToSwap(String requestId, bool approve);
}

class SupabaseDutyRequestGateway implements DutyRequestGateway {
  const SupabaseDutyRequestGateway();
  @override
  Future<void> respondToSwap(String requestId, bool approve) async {
    await Supabase.instance.client
        .rpc(
          'respond_to_duty_swap',
          params: {'p_request_id': requestId, 'p_approve': approve},
        )
        .timeout(const Duration(seconds: 30));
  }

  @override
  Future<List<Map<String, dynamic>>> swapOptions(String scheduleId) async {
    final rows = await Supabase.instance.client
        .rpc('available_duty_swaps', params: {'p_schedule_id': scheduleId})
        .timeout(const Duration(seconds: 20));
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<DutyRequestData> load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw StateError('Sign in again to view your requests.');
    final data = await Future.wait([
      DutyRequestService.upcomingSchedules(user.id),
      DutyRequestService.myRequests(user.id),
    ]);
    return DutyRequestData(schedules: data[0], requests: data[1]);
  }

  @override
  Future<void> submit({
    required String scheduleId,
    required String reason,
    required String requestType,
    required RequestLetter letter,
    String? targetScheduleId,
  }) => DutyRequestService.requestShiftChange(
    scheduleId: scheduleId,
    reason: reason,
    requestType: requestType,
    letter: letter,
    targetScheduleId: targetScheduleId,
  );

  @override
  Future<void> discard(RequestLetter letter) =>
      DutyRequestService.discardUnsubmittedLetter(letter);
}

String dutyRequestErrorMessage(Object error) {
  if (error is FormatException) return error.message;
  if (error is StateError) return error.message.toString();
  if (error is PostgrestException) return error.message;
  if (error is AuthException) return 'Your session expired. Sign in again.';
  if (error is StorageException) {
    if (error.statusCode == '401' || error.statusCode == '403') {
      return 'The letter upload was denied. Sign in again; if it continues, ask Operational Head to check request-letter access.';
    }
    if (error.statusCode == '413') {
      return 'The letter must be 5 MB or smaller.';
    }
    if (error.message.toLowerCase().contains('bucket')) {
      return 'Letter storage is unavailable. Ask Operational Head to enable request-letter uploads.';
    }
    return 'Letter upload failed. Check your connection and retry with this letter selected.';
  }
  if (error is TimeoutException) {
    return 'The request timed out. Keep this letter selected and retry; it will not create a duplicate request.';
  }
  return 'Could not confirm submission. Check your connection and retry with this letter selected.';
}

String dutyRequestLoadErrorMessage(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is AuthException) return 'Your session expired. Sign in again.';
  if (error is PostgrestException) {
    return 'Could not load your assigned duties. Refresh the page; if it continues, ask Operational Head to check your schedule.';
  }
  if (error is TimeoutException) {
    return 'Loading took too long. Check your connection and try again.';
  }
  return 'Could not load your assigned duties and requests. Check your connection and try again.';
}

/// PostgREST returns a to-one relation as a map (or null), while older schemas
/// can expose the same relation as a list. Accept both shapes so one completed
/// duty cannot crash the entire Letter Requests screen.
bool scheduleHasAttendance(Object? relation) => switch (relation) {
  Map<dynamic, dynamic> value => value.isNotEmpty,
  Iterable<dynamic> value => value.isNotEmpty,
  _ => false,
};

/// Stable storage identity makes a retry safe after an uncertain upload result.
/// The server's submit_duty_request RPC is idempotent for this same letter key.
Future<void> prepareRequestLetterUpload({
  required RequestLetter letter,
  required String userId,
  required Future<void> Function(String path) upload,
  required Future<bool> Function(String path) exists,
}) async {
  final retry = letter.pendingUploadPath != null;
  final path = letter.reservePath(userId);
  if (letter.uploadedPath != null) return;
  if (retry && await exists(path)) {
    letter.uploadedPath = path;
    return;
  }
  try {
    await upload(path);
  } on StorageException catch (error) {
    final duplicate =
        error.statusCode == '409' ||
        error.error == 'Duplicate' ||
        error.message.toLowerCase().contains('already exists');
    if (!duplicate || !await exists(path)) rethrow;
  }
  letter.uploadedPath = path;
}

class DutyRequestService {
  static final _client = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> upcomingSchedules(
    String userId,
  ) async {
    final rows = await _client
        .from('schedules')
        .select('*, attendance_sessions(id,status,clock_out_at)')
        .eq('user_id', userId)
        .inFilter('approval_status', ['approved', 'changed'])
        .or(
          'end_at.gt.${DateTime.now().toUtc().toIso8601String()},duty_date.eq.${DateTime.now().toUtc().add(const Duration(hours: 8)).toIso8601String().substring(0, 10)}',
        )
        .order('start_at');
    return rows;
  }

  static Future<void> requestShiftChange({
    required String scheduleId,
    required String reason,
    required String requestType,
    required RequestLetter letter,
    String? targetScheduleId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Your session expired. Sign in again.');
    if (!const ['absence', 'swap'].contains(requestType)) {
      throw const FormatException('Choose Absence or Swap.');
    }
    if (requestType == 'swap' && targetScheduleId == scheduleId) {
      throw const FormatException(
        'Choose another Guard’s duty to exchange with yours.',
      );
    }
    if (reason.trim().length < 5 || reason.trim().length > 1500) {
      throw const FormatException(
        'Enter a reason between 5 and 1500 characters.',
      );
    }
    final bucket = _client.storage.from('request-letters');
    await prepareRequestLetterUpload(
      letter: letter,
      userId: user.id,
      exists: (path) =>
          bucket.exists(path).timeout(const Duration(seconds: 20)),
      upload: (path) async {
        await bucket
            .uploadBinary(
              path,
              letter.bytes,
              fileOptions: FileOptions(
                contentType: letter.mimeType,
                upsert: false,
              ),
            )
            .timeout(const Duration(seconds: 45));
      },
    );
    letter.submissionUncertain = true;
    try {
      await _client
          .rpc(
            requestType == 'swap' && targetScheduleId != null
                ? 'submit_duty_exchange'
                : 'submit_duty_request',
            params: {
              'p_schedule_id': scheduleId,
              'p_reason': reason.trim(),
              if (requestType == 'swap' && targetScheduleId != null)
                'p_target_schedule_id': targetScheduleId,
              if (requestType != 'swap' || targetScheduleId == null)
                'p_request_type': requestType,
              'p_letter_path': letter.uploadedPath,
              'p_letter_name': letter.name,
            },
          )
          .timeout(const Duration(seconds: 30));
    } on PostgrestException {
      // The server returned an explicit failed transaction, not a lost result.
      letter.submissionUncertain = false;
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> myRequests(String userId) async {
    final rows = await _client
        .from('shift_swap_requests')
        .select('*, requested_duty:schedules!requested_schedule_id(*)')
        .or('requester_id.eq.$userId,target_guard_id.eq.$userId')
        .order('created_at', ascending: false)
        .limit(50);
    return rows
        .map(
          (row) => {
            ...row,
            'is_incoming':
                row['target_guard_id'] == userId &&
                row['requester_id'] != userId,
          },
        )
        .toList();
  }

  static Future<void> discardUnsubmittedLetter(RequestLetter letter) async {
    final path = letter.uploadedPath ?? letter.pendingUploadPath;
    if (path == null || letter.submissionUncertain) return;
    // RLS keeps a filed letter, even if a successful submission response was lost.
    await _client.storage.from('request-letters').remove([path]);
  }

  static Future<void> submitAccomplishment({
    required String scheduleId,
    required String summary,
    required String narrative,
    required String issues,
    required AccomplishmentPhoto photo,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Your session expired. Sign in again.');
    final bucket = _client.storage.from('accomplishment-photos');
    final retry = photo.uploadPath != null;
    final path = photo.reservePath(user.id);
    if (!photo.uploaded) {
      if (retry &&
          await bucket.exists(path).timeout(const Duration(seconds: 20))) {
        photo.uploaded = true;
      } else {
        await bucket
            .uploadBinary(
              path,
              photo.bytes,
              fileOptions: FileOptions(
                contentType: photo.mimeType,
                upsert: false,
              ),
            )
            .timeout(const Duration(seconds: 60));
        photo.uploaded = true;
      }
    }
    photo.submissionUncertain = true;
    try {
      await _client
          .rpc(
            'submit_accomplishment_report',
            params: {
              'p_schedule_id': scheduleId,
              'p_summary': summary.trim(),
              'p_detailed_narrative': narrative.trim(),
              'p_issues_encountered': issues.trim(),
              'p_photo_path': path,
              'p_photo_name': photo.name,
            },
          )
          .timeout(const Duration(seconds: 30));
    } on PostgrestException {
      photo.submissionUncertain = false;
      rethrow;
    }
  }

  static Future<void> discardAccomplishmentPhoto(
    AccomplishmentPhoto photo,
  ) async {
    if (photo.uploadPath == null || photo.submissionUncertain) return;
    await _client.storage.from('accomplishment-photos').remove([
      photo.uploadPath!,
    ]);
  }
}
