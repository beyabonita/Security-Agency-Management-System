import { deleteIncidentHandler } from "./handler.ts";

const actor = "11111111-1111-4111-8111-111111111111";
const incidentId = "22222222-2222-4222-8222-222222222222";
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
function fixture(
  options: {
    denied?: boolean;
    authFailed?: boolean;
    mediaFailed?: boolean;
    finishFailed?: boolean;
    deleted?: boolean;
    shared?: boolean;
    path?: string | null;
  } = {},
) {
  const calls: string[] = [];
  const service = {
    auth: {
      getUser: () => ({
        data: { user: options.authFailed ? null : { id: actor } },
        error: null,
      }),
    },
    rpc: (_name: string, args: { p_finish: boolean }) => {
      calls.push(args.p_finish ? "finish" : "begin");
      if (options.denied) return { data: null, error: { code: "42501" } };
      if (args.p_finish) {
        return {
          data: { deleted: true },
          error: options.finishFailed ? { message: "DB unavailable" } : null,
        };
      }
      return {
        data: {
          deleted: options.deleted || false,
          user_id: actor,
          video_path: options.path === undefined
            ? `${actor}/evidence.mp4`
            : options.path,
          video_shared: options.shared || false,
        },
        error: null,
      };
    },
    storage: {
      from: (bucket: string) => ({
        remove: (paths: string[]) => {
          calls.push("remove");
          assert(bucket === "incident-videos", "Wrong bucket");
          assert(paths.length === 1, "Must delete only the referenced video");
          return {
            error: options.mediaFailed
              ? { message: "Storage unavailable" }
              : null,
          };
        },
      }),
    },
  };
  const run = () =>
    deleteIncidentHandler(
      new Request("https://example.invalid/admin-delete-incident", {
        method: "POST",
        headers: {
          Authorization: "Bearer test-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ incidentId }),
      }),
      () =>
        service as unknown as ReturnType<
          typeof import("../_shared/api.ts").serviceClient
        >,
    );
  return { run, calls };
}
Deno.test("deletes Storage media before finalizing the database record", async () => {
  const f = fixture();
  const r = await f.run();
  assert(r.status === 200, "Expected success");
  assert(
    JSON.stringify(f.calls) === '["begin","remove","finish"]',
    "Wrong cleanup order",
  );
});
Deno.test("failed media cleanup keeps the report and does not pretend success", async () => {
  const f = fixture({ mediaFailed: true });
  const r = await f.run();
  assert(r.status === 502, "Expected storage failure");
  assert(!f.calls.includes("finish"), "Report must not be deleted");
});
Deno.test("database finalization failure tells the user to retry", async () => {
  const f = fixture({ finishFailed: true });
  const r = await f.run();
  assert(r.status === 500, "Expected failure");
  assert(
    (await r.json()).code === "delete_finish_failed",
    "Expected retry code",
  );
});
Deno.test("unauthorized role never touches Storage", async () => {
  const f = fixture({ denied: true });
  const r = await f.run();
  assert(r.status === 403, "Expected forbidden");
  assert(!f.calls.includes("remove"), "Must not remove media");
});
Deno.test("invalid session never calls the database", async () => {
  const f = fixture({ authFailed: true });
  assert((await f.run()).status === 401, "Expected unauthorized");
  assert(f.calls.length === 0, "No database access");
});
Deno.test("repeated completed deletion is safe", async () => {
  const f = fixture({ deleted: true });
  assert((await f.run()).status === 200, "Expected idempotent success");
  assert(f.calls.length === 1, "No second media removal");
});
Deno.test("video still used by another report is retained", async () => {
  const f = fixture({ shared: true });
  assert((await f.run()).status === 200, "Expected success");
  assert(!f.calls.includes("remove"), "Shared video retained");
});
Deno.test("foreign video path is rejected, never fetched or deleted", async () => {
  const f = fixture({ path: `${incidentId}/other.mp4` });
  assert((await f.run()).status === 409, "Expected invalid path");
  assert(!f.calls.includes("remove"), "Must not remove foreign video");
});
Deno.test("photo-only report does not call Storage", async () => {
  const f = fixture({ path: null });
  assert((await f.run()).status === 200, "Expected success");
  assert(!f.calls.includes("remove"), "No video to remove");
});
