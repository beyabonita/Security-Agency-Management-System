import { reject } from './api.ts';
export function personnelName(value: string): string {
  const name=value.trim().replace(/\s+/gu,' ');
  if(name && !/^[\p{L}\p{M} .’'\-]+$/u.test(name))reject(400,'Names may contain letters, spaces, apostrophes, hyphens and periods only.','invalid_name');
  return name.replace(/(^|[\s\-])\p{L}/gu,letter=>letter.toLocaleUpperCase());
}
