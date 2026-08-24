import { handleJsonPost } from "../_shared/api.ts";

// Sentinel Link has one beneficiary, TwentyTwenty Security Agency. Keeping a
// guarded tombstone prevents old clients from silently restoring the retired
// multi-client provisioning workflow.
Deno.serve((request) =>
  handleJsonPost(request, () => ({
    status: 410,
    data: {
      error:
        "Client provisioning is disabled. Sentinel Link is configured for TwentyTwenty Security Agency; use the IT Admin Accounts & Roles panel for platform access.",
      code: "client_provisioning_retired",
    },
  }))
);
