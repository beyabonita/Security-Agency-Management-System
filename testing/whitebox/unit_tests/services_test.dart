import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/user_profile_service.dart';
import 'package:flutter_application_1/services/user_role_service.dart';
import 'package:flutter_application_1/services/attendance_service.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'core_test.dart' as core;

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  core.serial=500;
  Object? response;
  int status=200;
  final calls=<http.Request>[];
  setUpAll(()async{
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url:'https://example.invalid',publishableKey:'unit-test-placeholder',debug:false,
      authOptions: const FlutterAuthClientOptions(persistSession:false,autoRefreshToken:false,detectSessionInUri:false),
      httpClient:MockClient((r)async{calls.add(r);return http.Response(jsonEncode(response),status,request:r,headers:{'content-type':'application/json'});}));
  });
  setUp((){calls.clear();response=null;status=200;});
  tearDownAll(()async{await Supabase.instance.dispose();});
  for(final role in ['user','inspector','admin','it_admin']){
    for(final active in [false,true]){
      final expected=role=='admin'?'admin':role=='it_admin'?'it_admin':role=='inspector'?'Inspector accounts use the web panel.':active?null:'Your account has been disabled. Contact your administrator.';
      core.wb('UserProfileService','validateGuardLogin','role and active branches',{'role':role,'active':active},expected,()async{response={'role':role,'active':active};return UserProfileService.validateGuardLogin('g');});
    }
  }
  core.wb('UserProfileService','validateGuardLogin','missing profile',null,'Account profile not found. Contact your administrator.',()async=>UserProfileService.validateGuardLogin('g'));
  core.wb('UserProfileService','validateGuardLogin','unknown active role must be denied',{'role':'owner','active':true},true,()async{response={'role':'owner','active':true};return await UserProfileService.validateGuardLogin('g')!=null;});
  core.wb('UserProfileService','getProfile','database error propagated','HTTP403',true,()async{status=403;response={'code':'42501','message':'denied'};try{await UserProfileService.getProfile('g');return false;}on PostgrestException{return true;}});
  core.wb('UserRoleService','getRole','profile role returned','admin','admin',()async{response={'role':'admin'};return UserRoleService.getRole('g');});
  core.wb('UserRoleService','currentUserRole','no auth session returns null',null,[null,0],()async=>[await UserRoleService.currentUserRole(),calls.length]);
  core.wb('UserRoleService','isAdmin','anonymous user denied',null,false,()async=>UserRoleService.isAdmin());
  core.wb('UserProfileService','registerDeviceIfNeeded','RPC body preserves device identity','device-fixture',{'p_device_id':'device-fixture'},()async{await UserProfileService.registerDeviceIfNeeded('g','device-fixture');expect(calls.single.url.path,endsWith('/rpc/register_device'));return jsonDecode(calls.single.body);});
  core.wb('AttendanceService','loadOpenSession','no open session',null,null,()async=>(await AttendanceService.loadOpenSession('g'))?.id);
  core.wb('AttendanceService','loadOpenSession','query scoped to owner and open status','g',['eq.g','eq.open','1'],()async{await AttendanceService.loadOpenSession('g');final q=calls.single.url.queryParameters;return [q['user_id'],q['status'],q['limit']];});
  core.wb('AttendanceService','recordEvent','RPC sends exact validated coordinates','clock_in;0;0',{'p_action':'clock_in','p_latitude':0.0,'p_longitude':0.0},()async{response=core.row();await AttendanceService.recordEvent(action:'clock_in',latitude:0,longitude:0);expect(calls.single.url.path,endsWith('/rpc/record_attendance_event'));return jsonDecode(calls.single.body);});
  core.wb('AttendanceService','recordEvent','invalid server response fails','scalar response',true,()async{response=42;try{await AttendanceService.recordEvent(action:'clock_in',latitude:0,longitude:0);return false;}on FormatException{return true;}});
  core.wb('AttendanceService','recordEvent','database denial propagates','HTTP403',true,()async{status=403;response={'code':'42501','message':'denied'};try{await AttendanceService.recordEvent(action:'clock_in',latitude:0,longitude:0);return false;}on PostgrestException{return true;}});
  core.wb('NotificationService','markRead','scoped notification RPC','n1',{'p_notification_id':'n1'},()async{await NotificationService.markRead('n1');expect(calls.single.url.path,endsWith('/rpc/mark_notification_read'));return jsonDecode(calls.single.body);});
  core.wb('NotificationService','acknowledge','acknowledgement RPC','n1',{'p_notification_id':'n1'},()async{await NotificationService.acknowledge('n1');expect(calls.single.url.path,endsWith('/rpc/acknowledge_notification'));return jsonDecode(calls.single.body);});
  for(final value in [3,null,'bad']) core.wb('NotificationService','markAllRead','numeric result or safe default',value,value is int?value:0,()async{response=value;return NotificationService.markAllRead();});
}
