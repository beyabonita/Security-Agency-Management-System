import { reject } from './api.ts';

export function philippineMobileNumber(value: unknown): string {
  if (typeof value !== 'string' || !/^09[0-9]{9}$/.test(value.trim())) {
    reject(400, 'Enter an 11-digit Philippine mobile number starting with 09.', 'invalid_mobile_number');
  }
  return value.trim();
}
