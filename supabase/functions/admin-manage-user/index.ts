import {
  ApiError,
  authenticatedUserId,
  backendFailure,
  handleJsonPost,
  logEvent,
  reject,
  serviceClient,
} from "../_shared/api.ts";
import {
  AUTH_EMAIL_DOMAIN,
  authProviderMessage,
  beneficiaryOrganizationId,
  databaseBusinessMessage,
  FIELD_ROLES,
  isAppRole,
  isEmploymentCategory,
  loadCallerProfile,
  type ManagedProfile,
  optionalBoolean,
  optionalString,
  PLATFORM_ROLES,
  usernameValid,
  uuidValid,
} from "../_shared/accounts.ts";

Deno.serve((request) =>
  handleJsonPost(request, async ({
    body,
    requestId,
  }) => {
    const service = serviceClient();
    const callerId = await authenticatedUserId(request, service);
    const caller = await loadCallerProfile(service, callerId);
    const isItAdmin = caller.role === "it_admin" && caller.active;
    const isHr = caller.role === "admin" && caller.active &&
      !!caller.organization_id;
    if (!isItAdmin && !isHr) {
      reject(
        403,
        "Only IT Admin or HR / Operations can manage accounts.",
        "forbidden",
      );
    }

    if (typeof body.action !== "string") {
      reject(400, "Account action is required.", "invalid_action");
    }
    if (body.action === "delete") {
      reject(
        409,
        "Account deletion is disabled to preserve attendance, schedules, reports, and incident records. Disable the account instead.",
        "account_deletion_disabled",
      );
    }
    if (body.action !== "update") {
      reject(400, "Invalid account action.", "invalid_action");
    }

    const targetId = optionalString(body, "userId", "Account ID", {
      min: 36,
      max: 36,
      normalize: (value) => value.trim(),
    });
    if (!targetId || !uuidValid(targetId)) {
      reject(400, "Choose a valid account.", "invalid_account_id");
    }

    const { data: targetData, error: targetError } = await service
      .from("profiles")
      .select(
        "id,username,email,first_name,middle_initial,last_name,role,active,organization_id,employment_category,device_id,device_locked",
      )
      .eq("id", targetId)
      .maybeSingle();
    if (targetError) {
      backendFailure(
        "The account record could not be loaded.",
        "target_profile_lookup_failed",
        targetError,
      );
    }
    if (!targetData || !isAppRole(targetData.role)) {
      reject(404, "Account not found.", "account_not_found");
    }
    const target = targetData as ManagedProfile;

    if (targetId === callerId) {
      reject(
        400,
        "Use a different IT Admin account to edit or disable your own account.",
        "self_management_blocked",
      );
    }
    if (
      isHr &&
      (
        target.organization_id !== caller.organization_id ||
        !FIELD_ROLES.includes(target.role as "user" | "inspector")
      )
    ) {
      reject(
        403,
        "HR / Operations can manage Guard and Inspector accounts in their own organization only.",
        "forbidden_target",
      );
    }
    if (
      isItAdmin &&
      !PLATFORM_ROLES.includes(target.role as "admin" | "it_admin")
    ) {
      reject(
        403,
        "IT Admin maintains IT and HR / Operations access. Guard and Inspector accounts are managed by HR / Operations.",
        "forbidden_target",
      );
    }

    const requestedRole = body.role === undefined ? target.role : body.role;
    if (!isAppRole(requestedRole)) {
      reject(400, "Choose a valid account role.", "invalid_role");
    }
    if (isHr && requestedRole !== target.role) {
      reject(
        403,
        "HR / Operations cannot change Guard and Inspector role types.",
        "forbidden_role",
      );
    }
    if (
      isItAdmin &&
      !PLATFORM_ROLES.includes(requestedRole as "admin" | "it_admin")
    ) {
      reject(
        403,
        "IT Admin may assign only IT Admin or HR / Operations Head roles.",
        "forbidden_role",
      );
    }
    const role = requestedRole;

    const active = optionalBoolean(body, "active", "Active status") ??
      target.active;
    const resetDevice = optionalBoolean(body, "resetDevice", "Reset device") ??
      false;
    const removesActiveItAdmin = target.role === "it_admin" && target.active &&
      (role !== "it_admin" || !active);
    if (removesActiveItAdmin) {
      const { count, error: countError } = await service
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("role", "it_admin")
        .eq("active", true);
      if (countError) {
        backendFailure(
          "The IT Admin safety check could not be completed.",
          "it_admin_count_failed",
          countError,
        );
      }
      if ((count ?? 0) <= 1) {
        reject(
          409,
          "The last active IT Admin must remain active and keep the IT Admin role.",
          "last_it_admin",
        );
      }
    }

    const username = optionalString(body, "username", "Username", {
      min: 3,
      max: 32,
      normalize: (value) => value.trim().toLowerCase(),
    }) ?? target.username;
    if (!usernameValid(username)) {
      reject(
        400,
        "Username must use 3–32 lowercase letters, numbers, dots, or underscores.",
        "invalid_username",
      );
    }
    const { data: duplicate, error: duplicateError } = await service
      .from("profiles")
      .select("id")
      .eq("username", username)
      .neq("id", targetId)
      .maybeSingle();
    if (duplicateError) {
      backendFailure(
        "The username availability check could not be completed.",
        "username_check_failed",
        duplicateError,
      );
    }
    if (duplicate) {
      reject(409, "That username is already in use.", "username_in_use");
    }

    let password = "";
    if (body.password !== undefined) {
      if (typeof body.password !== "string") {
        reject(400, "Password must be text.", "invalid_input");
      }
      password = body.password;
      if (password && (password.length < 6 || password.length > 128)) {
        reject(
          400,
          "Password must contain 6 to 128 characters.",
          "invalid_input",
        );
      }
    }

    const firstName = optionalString(body, "firstName", "First name", {
      min: 1,
      max: 100,
      normalize: (value) => value.trim(),
    }) ?? target.first_name;
    const middleInitial =
      optionalString(body, "middleInitial", "Middle initial", {
        max: 10,
        normalize: (value) => value.trim(),
      }) ?? target.middle_initial;
    const lastName = optionalString(body, "lastName", "Last name", {
      min: 1,
      max: 100,
      normalize: (value) => value.trim(),
    }) ?? target.last_name;

    const employmentValue = body.employmentCategory === undefined
      ? target.employment_category
      : body.employmentCategory;
    if (!isEmploymentCategory(employmentValue)) {
      reject(400, "Choose Regular or Contract duty.", "invalid_duty_category");
    }
    const employmentCategory = role === "user" ? employmentValue : "regular";

    let organizationId: string | null = isHr ? caller.organization_id : null;
    if (isItAdmin && role === "admin") {
      organizationId = await beneficiaryOrganizationId(service);
    }
    const authEmail = `${username}@${AUTH_EMAIL_DOMAIN}`;

    const { data: authRecord, error: authLookupError } = await service.auth
      .admin
      .getUserById(targetId);
    if (authLookupError || !authRecord.user) {
      backendFailure(
        "The authentication account could not be loaded.",
        "auth_account_lookup_failed",
        authLookupError ?? new Error("Auth user not found."),
      );
    }

    const previousProfile = {
      username: target.username,
      email: target.email,
      first_name: target.first_name,
      middle_initial: target.middle_initial,
      last_name: target.last_name,
      role: target.role,
      active: target.active,
      organization_id: target.organization_id,
      employment_category: target.employment_category,
      device_id: target.device_id,
      device_locked: target.device_locked,
    };
    const profileUpdate = {
      username,
      email: authEmail,
      first_name: firstName,
      middle_initial: middleInitial,
      last_name: lastName,
      role,
      active,
      organization_id: organizationId,
      employment_category: employmentCategory,
      ...(resetDevice ? { device_id: null, device_locked: false } : {}),
    };
    const { data: updatedProfile, error: profileError } = await service
      .from("profiles")
      .update(profileUpdate)
      .eq("id", targetId)
      .select("id")
      .maybeSingle();
    if (profileError || !updatedProfile) {
      const businessMessage = databaseBusinessMessage(profileError);
      if (businessMessage) {
        throw new ApiError(
          409,
          businessMessage,
          "profile_update_rejected",
          { cause: profileError },
        );
      }
      backendFailure(
        "The account profile could not be updated. Try again or contact support with the request ID.",
        "profile_update_failed",
        profileError ?? new Error("Profile row was not returned."),
      );
    }

    const authUpdate: Record<string, unknown> = {
      email: authEmail,
      user_metadata: {
        ...(authRecord.user.user_metadata ?? {}),
        username,
        first_name: firstName,
        last_name: lastName,
      },
    };
    if (password) authUpdate.password = password;
    const { error: authUpdateError } = await service.auth.admin.updateUserById(
      targetId,
      authUpdate,
    );
    if (authUpdateError) {
      const { data: rollback, error: rollbackError } = await service
        .from("profiles")
        .update(previousProfile)
        .eq("id", targetId)
        .select("id")
        .maybeSingle();
      if (rollbackError || !rollback) {
        logEvent("error", "account_update_rollback_failed", requestId, {
          actorId: callerId,
          targetId,
          error: rollbackError?.message ?? "Profile row was not returned.",
        });
        backendFailure(
          "The account update could not be completed or rolled back. Contact support with the request ID.",
          "account_update_rollback_failed",
          rollbackError ?? authUpdateError,
        );
      }
      throw new ApiError(
        400,
        authProviderMessage(authUpdateError),
        "auth_account_update_failed",
        { cause: authUpdateError },
      );
    }

    const changedFields = Object.entries(profileUpdate)
      .filter(([key, value]) => {
        const previousKey = key as keyof typeof previousProfile;
        return previousProfile[previousKey] !== value;
      })
      .map(([key]) => key);
    if (password) changedFields.push("password");
    if (resetDevice) changedFields.push("device_registration");
    logEvent("info", "account_updated", requestId, {
      actorId: callerId,
      changedFields: [...new Set(changedFields)],
      organizationId,
      role,
      targetId,
    });
    return { data: { ok: true } };
  })
);
