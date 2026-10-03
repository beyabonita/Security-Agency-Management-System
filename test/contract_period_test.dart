import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/contract_period.dart';

void main() {
  ContractPeriod contract([
    String? start = '2026-09-05',
    String? end = '2026-09-06',
  ]) => ContractPeriod.fromProfile({
    'employment_category': 'contract',
    'contract_start_date': start,
    'contract_end_date': end,
  });
  test('Regular has no expiry', () {
    expect(
      ContractPeriod.fromProfile({
        'employment_category': 'regular',
      }).timeInBlockReason(DateTime.utc(2100)),
      isNull,
    );
  });
  test('Contract start uses Philippine midnight', () {
    expect(
      contract().timeInBlockReason(DateTime.parse('2026-09-04T15:59:59Z')),
      contains('not started'),
    );
    expect(
      contract().timeInBlockReason(DateTime.parse('2026-09-04T16:00:00Z')),
      isNull,
    );
  });
  test('End is inclusive through Philippine end of day', () {
    expect(
      contract().timeInBlockReason(DateTime.parse('2026-09-06T15:59:59Z')),
      isNull,
    );
    expect(
      contract().timeInBlockReason(DateTime.parse('2026-09-06T16:00:00Z')),
      contains('expired'),
    );
  });
  test('Missing and reversed contract dates fail closed', () {
    expect(contract(null, null).configured, isFalse);
    expect(contract('2026-09-06', '2026-09-05').configured, isFalse);
    expect(
      contract(null, null).label(DateTime.now()),
      contains('Set contract dates'),
    );
  });
  test('Invalid calendar dates are not normalized into another month', () {
    expect(contract('2026-02-30', '2026-03-05').configured, isFalse);
  });
  test('Guard can see exact contract and expiry', () {
    expect(
      contract().label(DateTime.utc(2027)),
      '2026-09-05 – 2026-09-06 · Expired',
    );
  });
}
