// Only the external SDK boundary is substituted. Production handlers and
// validation functions are imported unchanged and executed by Deno.test.
export type SupabaseClient = any;
export function createClient(..._args: unknown[]): SupabaseClient {
  const client = (globalThis as any).__whiteboxClient;
  if (!client) throw new Error('No fake client configured; live access prohibited');
  return client;
}
