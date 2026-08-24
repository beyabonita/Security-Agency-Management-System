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
  APP_ROLES,
  AUTH_EMAIL_DOMAIN,
  authProviderMessage,
  beneficiaryOrganizationId,
  FIELD_ROLES,
  isAppRole,
  isEmploymentCategory,
  loadCallerProfile,
  optionalString,
  PLATFORM_ROLES,
  usernameValid,
} from "../_shared/accounts.ts";

Deno.serve((request) =>
  handleJsonPost(request, async ({
    body,
    requestId,
  }) => {
    const service = serviceClient();
    const callerId = await authenticatedUserId(request, service);
    const caller = await loadCallerProfile(service, callerId);

    const isPlatformAdmin = caller.role === "it_admin" && caller.active;
    const isHr = caller.role === "admin" && caller.active &&
      !!caller.organization_id;
    if (!isPlatformAdmin && !isHr) {
      reject(
        403,
        "Only IT Admin or an active HR / Operations Head can create accounts.",
        "forbidden",
      );
    }

    const requestedEmail = optionalString(body, "email", "Email", {
      max: 320,
      normalize: (value) => value.trim().toLowerCase(),
    }) ?? "";
    const requestedUsername = optionalString(body, "username", "Username", {
      max: 32,
      normalize: (value) => value.trim().toLowerCase(),
    }) ?? "";
    const username = requestedUsername ||
      (requestedEmail.endsWith(`@${AUTH_EMAIL_DOMAIN}`)
        ? requestedEmail.slice(0, -(`@${AUTH_EMAIL_DOMAIN}`).length)
        : "");
    const authEmail = `${username}@${AUTH_EMAIL_DOMAIN}`;

    if (typeof body.password !== "string") {
      reject(400, "Password is required.", "invalid_input");
    }
    const password = body.password;
    if (password.length < 6 || password.length > 128) {
      reject(
        400,
        "Password must contain 6 to 128 characters.",
        "invalid_input",
      );
    }

    const roleValue = body.role ?? "user";
    if (!isAppRole(roleValue)) {
      reject(400, "Choose a valid account role.", "invalid_role");
    }
    const role = roleValue;
    if (isHr && !FIELD_ROLES.includes(role as "user" | "inspector")) {
      reject(
        403,
        "HR / Operations may create Guard and Inspector accounts only.",
        "forbidden_role",
      );
    }
    if (
      isPlatformAdmin &&
      !PLATFORM_ROLES.includes(role as "admin" | "it_admin")
    ) {
      reject(
        403,
        "IT Admin may create IT Admin and HR / Operations Head accounts only. HR / Operations manages Guard and Inspector accounts.",
        "forbidden_role",
      );
    }
    if (!APP_ROLES.includes(role)) {
      reject(400, "Choose a valid account role.", "invalid_role");
    }

    if (!usernameValid(username)) {
      reject(
        400,
        "Username must use 3–32 lowercase letters, numbers, dots, or underscores.",
        "invalid_username",
      );
    }
    if (requestedEmail && requestedEmail !== authEmail) {
      reject(
        400,
        "Account email must match the username sign-in format.",
        "invalid_email_alias",
      );
    }

    const firstName = optionalString(body, "firstName", "First name", {
      max: 100,
      normalize: (value) => value.trim(),
    }) ?? "";
    const middleInitial =
      optionalString(body, "middleInitial", "Middle initial", {
        max: 10,
        normalize: (value) => value.trim(),
      }) ?? "";
    const lastName = optionalString(body, "lastName", "Last name", {
      max: 100,
      normalize: (value) => value.trim(),
    }) ?? "";

    const employmentValue = body.employmentCategory ?? "regular";
    if (!isEmploymentCategory(employmentValue)) {
      reject(400, "Choose Regular or Contract duty.", "invalid_duty_category");
    }
    const employmentCategory = employmentValue;

    let targetOrganizationId: string | null = null;
    if (isHr) {
      targetOrganizationId = caller.organization_id;
    } else if (role === "admin") {
      targetOrganizationId = await beneficiaryOrganizationId(service);
    }

    const { data: duplicate, error: duplicateError } = await service
      .from("profiles")
      .select("id")
      .eq("username", username)
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

    const { data: authData, error: authError } = await service.auth.admin
      .createUser({
        email: authEmail,
        password,
        email_confirm: true,
        user_metadata: {
          username,
          first_name: firstName,
          last_name: lastName,
        },
      });
    if (authError || !authData.user) {
      throw new ApiError(
        400,
        authProviderMessage(authError),
        "auth_account_create_failed",
        { cause: authError },
      );
    }

    const targetId = authData.user.id;
    const { data: profile, error: profileError } = await service
      .from("profiles")
      .update({
        username,
        email: authEmail,
        first_name: firstName,
        middle_initial: middleInitial,
        last_name: lastName,
        role,
        organization_id: targetOrganizationId,
        employment_category: role === "user" ? employmentCategory : "regular",
      })
      .eq("id", targetId)
      .select("id")
      .maybeSingle();

    if (profileError || !profile) {
      const { error: rollbackError } = await service.auth.admin.deleteUser(
        targetId,
      );
      if (rollbackError) {
        logEvent("error", "account_create_rollback_failed", requestId, {
          actorId: callerId,
          targetId,
          error: rollbackError.message,
        });
      }
      backendFailure(
        rollbackError
          ? "Account provisioning could not be completed or rolled back. Contact support with the request ID."
          : "Account provisioning could not be completed. No account was created.",
        rollbackError
          ? "account_create_rollback_failed"
          : "profile_create_failed",
        profileError ??
          new Error("The Auth profile trigger did not create a profile row."),
      );
    }

    logEvent("info", "account_created", requestId, {
      actorId: callerId,
      organizationId: targetOrganizationId,
      role,
      targetId,
    });
    return { data: { id: targetId } };
  })
);
