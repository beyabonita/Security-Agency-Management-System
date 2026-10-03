import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/utils/auth_username.dart';
import 'package:flutter_application_1/services/user_profile_service.dart';
import 'package:flutter_application_1/services/attendance_service.dart';
import 'package:flutter_application_1/services/schedule_service.dart';
import 'package:flutter_application_1/services/geofence_service.dart';
import 'package:flutter_application_1/services/location_integrity_service.dart';
import 'package:flutter_application_1/services/duty_request_service.dart';
import 'package:flutter_application_1/models/geofence_site.dart';
import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/models/contract_period.dart';
import 'package:flutter_application_1/models/dtr_alignment.dart';
import 'package:flutter_application_1/models/request_letter.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

int serial = 0;
void wb(String module, String method, String scenario, Object? input,
    Object? expected, FutureOr<Object?> Function() run) {
  final id = 'WB-${(++serial).toString().padLeft(3, '0')}';
  test('$id $module.$method: $scenario', () async {
    final meta = {'id': id, 'module': module, 'method': method,
      'scenario': scenario, 'input': input, 'expected': expected,
      'framework': 'flutter_test', 'source': 'testing/whitebox/unit_tests/core_test.dart'};
    try {
      final actual = await run();
      print('WB_EVIDENCE ${jsonEncode({...meta, 'actual': actual, 'at': DateTime.now().toUtc().toIso8601String()})}');
      expect(actual, equals(expected));
    } catch (e) {
      print('WB_ERROR ${jsonEncode({...meta, 'error': e.toString()})}');
      rethrow;
    }
  });
}
String thrown(void Function() run) {
  try { run(); return 'no exception'; } catch(e) { return e.runtimeType.toString(); }
}
final now = DateTime.utc(2026, 9, 5, 0);
Map<String,dynamic> row() => {'id':'s1', 'schedule_id':'d1', 'duty_date':'2026-09-05',
  'scheduled_start_at':'2026-09-05T00:00:00Z', 'scheduled_end_at':'2026-09-05T08:00:00Z',
  'clock_in_at':'2026-09-05T00:00:00Z', 'clock_out_at':'2026-09-05T08:00:00Z', 'status':'closed'};
RequestLetter letter() => RequestLetter(name:'letter.pdf',bytes:Uint8List.fromList('%PDF-test'.codeUnits));

void main() {
  for (final entry in <String,bool>{'ab':false,'abc':true,'a'*32:true,'a'*33:false,'':false,'  GUARD_01  ':true,'a-b':false,'a b':false,'éab':false,'a.b':true}.entries) {
    wb('auth_username','validateUsername','length and character validation',entry.key,entry.value,()=>validateUsername(entry.key)==null);
  }
  wb('auth_username','normalizeUsername','trim and lower case',' Guard_1 ','guard_1',()=>normalizeUsername(' Guard_1 '));
  wb('auth_username','resolveAuthEmail','legacy email',' USER@Example.com ','user@example.com',()=>resolveAuthEmail(' USER@Example.com '));
  wb('auth_username','usernameToAuthEmail','synthetic email',' Guard ','guard@$authEmailDomain',()=>usernameToAuthEmail(' Guard '));
  wb('auth_username','resolveAuthEmail','username route','Guard','guard@$authEmailDomain',()=>resolveAuthEmail('Guard'));
  for(final entry in <(Map<String,dynamic>?,String)>[(null,''),({},''),({'username':'g','email':'old@x'},'g'),({'email':'guard@$authEmailDomain'},'guard'),({'email':'legacy@x'},'legacy@x'),({'username':12},'12')]) {
    wb('auth_username','displayLoginId','profile fallback',entry.$1,entry.$2,()=>displayLoginId(entry.$1));
  }
  wb('auth_username','validateUsername','incorrect runtime type',123,'_TypeError',()=>thrown(()=>validateUsername(123 as dynamic)));
  wb('UserProfileService','displayName','missing names',{},'Security Guard',()=>UserProfileService.displayName({}));
  wb('UserProfileService','displayName','middle initial',{'first_name':'Ana','middle_initial':'B','last_name':'Cruz'},'Ana B. Cruz',()=>UserProfileService.displayName({'first_name':'Ana','middle_initial':'B','last_name':'Cruz'}));
  for(final seconds in [-46,-45,0,45,46]) {
    wb('LocationIntegrityService','validationError','45-second absolute age boundary',{'ageSeconds':seconds},seconds.abs()<=45,()=>LocationIntegrityService.validationError(latitude:0,longitude:0,accuracyMeters:1,capturedAt:now.subtract(Duration(seconds:seconds)),isMocked:false,now:now)==null);
  }
  for(final entry in <(double,double,bool)>[(90,180,true),(-90,-180,true),(90.01,0,false),(0,180.01,false),(double.nan,0,false),(0,double.infinity,false)]) {
    wb('LocationIntegrityService','validationError','coordinate bounds','${entry.$1},${entry.$2}',entry.$3,()=>LocationIntegrityService.validationError(latitude:entry.$1,longitude:entry.$2,accuracyMeters:1,capturedAt:now,isMocked:false,now:now)==null);
  }
  for(final a in [0.0,-1.0,double.nan,double.infinity,0.1]) {
    wb('LocationIntegrityService','validationError','GPS accuracy',a.toString(),a.isFinite&&a>0,()=>LocationIntegrityService.validationError(latitude:0,longitude:0,accuracyMeters:a,capturedAt:now,isMocked:false,now:now)==null);
  }
  wb('LocationIntegrityService','validationError','mock location rejected',true,false,()=>LocationIntegrityService.validationError(latitude:0,longitude:0,accuracyMeters:1,capturedAt:now,isMocked:true,now:now)==null);
  const site = GeofenceSite(id:'a',label:'A',latitude:0,longitude:0,radiusMeters:100);
  const zero = GeofenceSite(id:'z',label:'Z',latitude:0,longitude:0,radiusMeters:0);
  wb('GeofenceService','isWithinAnySite','no sites',[],false,()=>GeofenceService.isWithinAnySite(const LatLng(0,0),[]));
  wb('GeofenceService','isWithinAnySite','center included','0,0; radius100',true,()=>GeofenceService.isWithinAnySite(const LatLng(0,0),[site]));
  wb('GeofenceService','isWithinAnySite','outside radius','1,1; radius100',false,()=>GeofenceService.isWithinAnySite(const LatLng(1,1),[site]));
  wb('GeofenceService','isWithinAnySite','zero-radius equality','0,0; radius0',true,()=>GeofenceService.isWithinAnySite(const LatLng(0,0),[zero]));
  wb('GeofenceService','nearestSite','empty sites',[],null,()=>GeofenceService.nearestSite(const LatLng(0,0),[])?.id);
  wb('GeofenceService','nearestSite','stable equal-distance tie',['a','z'],'a',()=>GeofenceService.nearestSite(const LatLng(0,0),[site,zero])?.id);
  wb('GeofenceService','loadSitesForUser','empty ids avoid database',[],0,() async=>(await GeofenceService.loadSitesForUser([])).length);
  for(final entry in <(String,String,bool)>[('2026-09-05','2026-09-05',true),('2026-09-06','2026-09-05',false),('2026-02-30','2026-09-05',false),('','',false),('2028-02-29','2028-02-29',true)]) {
    wb('ContractPeriod','configured','real dates and ordered range',[entry.$1,entry.$2],entry.$3,()=>ContractPeriod.fromProfile({'employment_category':'contract','contract_start_date':entry.$1,'contract_end_date':entry.$2}).configured);
  }
  for(final entry in <(String,bool)>[('2026-09-04T15:59:59Z',false),('2026-09-04T16:00:00Z',true),('2026-09-05T15:59:59Z',true),('2026-09-05T16:00:00Z',false)]) {
    wb('ContractPeriod','timeInBlockReason','inclusive Manila date boundaries',entry.$1,entry.$2,()=>ContractPeriod.fromProfile({'employment_category':'contract','contract_start_date':'2026-09-05','contract_end_date':'2026-09-05'}).timeInBlockReason(DateTime.parse(entry.$1))==null);
  }
  wb('ContractPeriod','timeInBlockReason','regular staff unrestricted',{},null,()=>ContractPeriod.fromProfile({}).timeInBlockReason(now));
  for(final date in ['2026-02-29','2026-13-01','2026-00-01','2026-01-00','bad','']) {
    wb('DtrAlignment','cutoffForDutyDate','invalid calendar date',date,null,()=>DtrAlignment.cutoffForDutyDate(date)?.endDate);
  }
  for(final entry in <String,String>{'2028-02-29':'2028-02-29','2026-09-15':'2026-09-15','2026-09-16':'2026-09-30','2026-12-31':'2026-12-31'}.entries) {
    wb('DtrAlignment','cutoffForDutyDate','cutoff boundary',entry.key,entry.value,()=>DtrAlignment.cutoffForDutyDate(entry.key)?.endDate);
  }
  for(final p in [null,' MORNING ','afternoon','overtime','invalid']) {
    wb('DtrAlignment','normalizePeriod','normalize explicit period',p,p==null||p=='invalid'?'auto':p.trim().toLowerCase(),()=>DtrAlignment.normalizePeriod(p));
  }
  for(final entry in <(String,bool,String)>[('2026-09-05T04:00:00Z',true,'Afternoon IN'),('2026-09-05T04:00:00Z',false,'Morning OUT'),('2026-09-06T00:00:00Z',true,'Morning IN (+1)'),('2026-09-04T00:00:00Z',false,'Morning OUT (-1)')]) {
    wb('DtrAlignment','cellLabel','noon and day-offset decisions',[entry.$1,entry.$2],entry.$3,()=>DtrAlignment.cellLabel(DateTime.parse(entry.$1),isTimeIn:entry.$2,dutyDate:'2026-09-05'));
  }
  for(final key in ['scheduled_start_at','scheduled_end_at','clock_in_at']) {
    wb('AttendanceSession','fromRow','required timestamp rejected',{'missing':key},'FormatException',()=>thrown(()=>AttendanceSession.fromRow(row()..remove(key))));
  }
  wb('AttendanceSession','workedDuration','eight-hour calculation',row(),480,()=>AttendanceSession.fromRow(row()).workedDuration.inMinutes);
  wb('AttendanceSession','workedDuration','reversed punches clamp to zero','out before in',0,()=>AttendanceSession.fromRow(row()..['clock_out_at']='2026-09-04T23:00:00Z').workedDuration.inMinutes);
  wb('AttendanceSession','lateDuration','late punch','00:15',15,()=>AttendanceSession.fromRow(row()..['clock_in_at']='2026-09-05T00:15:00Z').lateDuration.inMinutes);
  wb('AttendanceSession','undertimeDuration','early departure','07:30',30,()=>AttendanceSession.fromRow(row()..['clock_out_at']='2026-09-05T07:30:00Z').undertimeDuration.inMinutes);
  wb('AttendanceSession','fromRow','malformed supplied clock-out must not disappear','clock_out_at=garbage','FormatException',()=>thrown(()=>AttendanceSession.fromRow(row()..['clock_out_at']='garbage')));
  for(final entry in <int,String>{-1:'0 min',0:'0 min',1:'1 min',60:'1 hr',120:'2 hrs',61:'1h 1m'}.entries) {
    wb('AttendanceService','formatDuration','duration display boundaries',entry.key,entry.value,()=>AttendanceService.formatDuration(Duration(minutes:entry.key)));
  }
  for(final entry in <(String,bool,bool)>[('clock_in',true,true),('clock_in',false,false),('clock_out',false,true),('clock_out',true,false)]) {
    wb('AttendanceService','blockReasonForAction','duplicate and missing punch',[entry.$1,entry.$2],entry.$3,()=>AttendanceService.blockReasonForAction(entry.$1,entry.$2?AttendanceSession.fromRow(row()..['clock_out_at']=null..['status']='open'):null)!=null);
  }
  wb('ScheduleService','visibleSchedules','owner and status restrictions','own approved/changed/draft/cancelled; foreign approved',['a','b'],()=>ScheduleService.visibleSchedules([{'id':'a','user_id':'g','approval_status':'approved'},{'id':'b','user_id':'g','approval_status':'changed'},{'id':'c','user_id':'g','approval_status':'draft'},{'id':'d','user_id':'g','approval_status':'cancelled'},{'id':'e','user_id':'other','approval_status':'approved'}],'g').map((r)=>r['id']).toList());
  wb('ScheduleService','locationIdsFromSchedules','deduplicate and omit missing',['a','a','',null],['a'],()=>ScheduleService.locationIdsFromSchedules([{'location_id':'a'},{'location_id':'a'},{'location_id':''},{}]));
  wb('ScheduleService','isScheduleEnded','end equality','end=now',true,()=>ScheduleService.isScheduleEnded({'end_at':now.toIso8601String()},now));
  wb('ScheduleService','isScheduleEnded','invalid end',{'end_at':45},false,()=>ScheduleService.isScheduleEnded({'end_at':45},now));
  wb('ScheduleService','scheduleDutyDate','fallback to Manila start',{'start_at':'2026-09-04T16:00:00Z'},'2026-09-05',()=>ScheduleService.scheduleDutyDate({'start_at':'2026-09-04T16:00:00Z'}));
  for(final entry in <(String,List<int>,bool)>[('ok.pdf','%PDF-x'.codeUnits,true),('ok.JPG',[255,216,255],true),('ok.png',[137,80,78,71,13,10,26,10],true),('../ok.pdf','%PDF-x'.codeUnits,false),('ok.exe','%PDF-x'.codeUnits,false),('ok.pdf',[],false),('ok.pdf',[1,2,3],false),('','%PDF-x'.codeUnits,false)]) {
    wb('RequestLetter','constructor','filename, content signature and empty bytes',{'name':entry.$1,'bytes':entry.$2},entry.$3,()=>thrown(()=>RequestLetter(name:entry.$1,bytes:Uint8List.fromList(entry.$2)))=='no exception');
  }
  for(final size in [RequestLetter.maxBytes,RequestLetter.maxBytes+1]) {
    wb('RequestLetter','constructor','5MB boundary',size,size==RequestLetter.maxBytes,(){final b=Uint8List(size)..setAll(0,'%PDF-'.codeUnits);return thrown(()=>RequestLetter(name:'a.pdf',bytes:b))=='no exception';});
  }
  wb('RequestLetter','reservePath','stable retry key','same user twice',true,(){final l=letter();return l.reservePath('g')==l.reservePath('g');});
  wb('RequestLetter','reservePath','cross-account retry forbidden',['g','other'],'StateError',(){final l=letter()..reservePath('g');return thrown(()=>l.reservePath('other'));});
  wb('DutyRequestService','prepareRequestLetterUpload','successful retry does not upload twice','two attempts',1,()async{final l=letter();var n=0;for(var i=0;i<2;i++){await prepareRequestLetterUpload(letter:l,userId:'g',upload:(_)async{n++;},exists:(_)async=>false);}return n;});
  wb('DutyRequestService','prepareRequestLetterUpload','lost response recovered using stable object','first upload throws TimeoutException',[1,true],()async{final l=letter();var n=0;try{await prepareRequestLetterUpload(letter:l,userId:'g',upload:(_)async{n++;throw TimeoutException('lost');},exists:(_)async=>false);}on TimeoutException{}await prepareRequestLetterUpload(letter:l,userId:'g',upload:(_)async{n++;},exists:(_)async=>true);return [n,l.uploadedPath==l.pendingUploadPath];});
  for(final exists in [false,true]) {
    wb('DutyRequestService','prepareRequestLetterUpload','duplicate requires confirmed object',{'duplicate409':true,'exists':exists},exists,()async{final l=letter();try{await prepareRequestLetterUpload(letter:l,userId:'g',upload:(_)async=>throw const StorageException('Duplicate',statusCode:'409'),exists:(_)async=>exists);return true;}on StorageException{return false;}});
  }
  for(final entry in <(Object?,bool)>[(null,false),({},false),([],false),({'id':1},true),([1],true),('invalid',false)]) {
    wb('DutyRequestService','scheduleHasAttendance','database relation shapes',entry.$1,entry.$2,()=>scheduleHasAttendance(entry.$1));
  }
}
