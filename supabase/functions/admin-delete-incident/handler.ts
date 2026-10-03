import {
  authenticatedUserId,
  backendFailure,
  handleJsonPost,
  logEvent,
  reject,
  serviceClient,
} from "../_shared/api.ts";
import { uuidValid } from "../_shared/accounts.ts";

// Inject the client in tests; production always verifies the bearer token with Auth.
export function deleteIncidentHandler(
  request: Request,
  createService = serviceClient,
) {
  return handleJsonPost(request, async ({ body, requestId }) => {
    const service = createService();
    const actorId = await authenticatedUserId(request, service);
    if (typeof body.incidentId !== "string" || !uuidValid(body.incidentId)) {
      reject(400, "Choose a valid emergency report.", "invalid_incident");
    }
    const { data: incident, error: beginError } = await service.rpc(
      "manage_incident_deletion",
      {
        p_incident_id: body.incidentId,
        p_actor_id: actorId,
        p_finish: false,
      },
    );
    if (beginError) {
      if (beginError.code === "42501") {
        reject(
          403,
          "Only Admin can delete emergency reports.",
          "forbidden",
        );
      }
      if (beginError.code === "P0002") {
        reject(404, "Report not found or no longer accessible.", "not_found");
      }
      backendFailure(
        "Could not start deletion. The report has been kept. Try again.",
        "delete_start_failed",
        beginError,
      );
    }
    if (!incident) {
      backendFailure(
        "Could not load the report for deletion.",
        "missing_incident",
        new Error("Empty deletion response"),
      );
    }
    if (incident.deleted) return { data: { ok: true, alreadyDeleted: true } };
    if (incident.video_path && !incident.video_shared) {
      // Never accept a caller-supplied path, another user's folder, or a URL.
      const prefix = `${incident.user_id}/`;
      const name = String(incident.video_path).slice(prefix.length);
      if (
        !String(incident.video_path).startsWith(prefix) ||
        !/^[A-Za-z0-9._-]+$/.test(name) || name === "." || name === ".."
      ) {
        reject(
          409,
          "This legacy video needs IT review before deletion. The report has been kept.",
          "unsafe_video_path",
        );
      }
      const { error: mediaError } = await service.storage.from(
        "incident-videos",
      ).remove([incident.video_path]);
      if (mediaError) {
        backendFailure(
          "Video cleanup failed. The report is still listed; retry Delete report.",
          "media_cleanup_failed",
          mediaError,
          502,
        );
      }
    }
    const { error: finishError } = await service.rpc(
      "manage_incident_deletion",
      {
        p_incident_id: body.incidentId,
        p_actor_id: actorId,
        p_finish: true,
      },
    );
    if (finishError) {
      backendFailure(
        "Cleanup could not be finalized. Retry Delete report to finish.",
        "delete_finish_failed",
        finishError,
      );
    }
    logEvent("info", "incident_deleted", requestId, {
      actorId,
      incidentId: body.incidentId,
    });
    return { data: { ok: true } };
  });
}
