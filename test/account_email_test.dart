import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/utils/auth_username.dart';
void main() {
 test('real emails normalize without making aliases', () {
  expect(validateEmail(' Guard.Name+post@Gmail.com '), isNull);
  expect(resolveAuthEmail(' Guard.Name+post@Gmail.com '), 'guard.name+post@gmail.com');
  expect(displayLoginId({'username':'internal','email':'guard@gmail.com'}),'guard@gmail.com');
 });
 test('invalid and synthetic addresses are rejected for email entry', () {
  for(final email in ['name','a@asamanion-26858.auth','a..b@gmail.com','.a@gmail.com','a.@gmail.com','a@-mail.com','a @gmail.com']) {
   expect(validateEmail(email),isNotNull,reason:email);
  }
 });
 test('existing usernames still sign in during migration; aliases are not displayed as mailboxes', () {
  expect(resolveAuthEmail(' Old.Guard '),'old.guard@asamanion-26858.auth');
  expect(displayLoginId({'email':'old.guard@asamanion-26858.auth'}),'Email not added');
 });
}
