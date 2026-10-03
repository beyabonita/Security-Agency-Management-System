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
  authProviderMessage,
  beneficiaryOrganizationId,
  emailValid,
  FIELD_ROLES,
  isAppRole,
  isEmploymentCategory,
  loadCallerProfile,
  optionalString,
  PLATFORM_ROLES,
} from "../_shared/accounts.ts";

import { contractPeriod } from "../_shared/contract-period.ts";
import { passwordError } from "../_shared/password-policy.ts";

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
        "Only IT Admin or an active Admin can create accounts.",
        "forbidden",
      );
    }

    const authEmail = optionalString(body, "email", "Email", {
      max: 254,
      normalize: (value) => value.trim().toLowerCase(),
    }) ?? "";
    if (!emailValid(authEmail)) {
      reject(
        400,
        "Enter a valid email address, such as name@gmail.com.",
        "invalid_email",
      );
    }
    // Retain the legacy internal field for compatibility; email is the login identity.
    const username = "u_" +
      crypto.randomUUID().replaceAll("-", "").slice(0, 30);

    if (typeof body.password !== "string") {
      reject(400, "Password is required.", "invalid_input");
    }
    const password = body.password;
    const invalidPassword = passwordError(password);
    if (invalidPassword) {
      reject(
        400,
        invalidPassword,
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
        "Admin may create Guard and Inspector accounts only.",
        "forbidden_role",
      );
    }
    if (
      isPlatformAdmin &&
      !PLATFORM_ROLES.includes(role as "admin" | "it_admin")
    ) {
      reject(
        403,
        "IT Admin may create IT Admin and Admin accounts only. Admin manages Guard and Inspector accounts.",
        "forbidden_role",
      );
    }
    if (!APP_ROLES.includes(role)) {
      reject(400, "Choose a valid account role.", "invalid_role");
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
    const mobileNumber =
      optionalString(body, "mobileNumber", "Mobile number", {
        max: 20,
        normalize: (value) => value.trim(),
      }) ?? null;
    if (mobileNumber && !/^09[0-9]{9}$/.test(mobileNumber)) {
      reject(
        400,
        "Enter an 11-digit mobile number starting with 09 (e.g. 09171234567).",
        "invalid_mobile_number",
      );
    }

    const employmentValue = body.employmentCategory ?? "regular";
    if (!isEmploymentCategory(employmentValue)) {
      reject(400, "Choose Regular or Contract duty.", "invalid_duty_category");
    }
    const employmentCategory = employmentValue;
    const contract = contractPeriod(
      role === "user" ? employmentCategory : "regular",
      body.contractStartDate,
      body.contractEndDate,
    );
    if (contract.error) reject(400, contract.error, "invalid_contract_period");

    let targetOrganizationId: string | null = null;
    if (isHr) {
      targetOrganizationId = caller.organization_id;
    } else if (role === "admin") {
      targetOrganizationId = await beneficiaryOrganizationId(service);
    }

    const { data: duplicate, error: duplicateError } = await service
      .from("profiles")
      .select("id")
      .eq("email", authEmail)
      .maybeSingle();
    if (duplicateError) {
      backendFailure(
        "The email availability check could not be completed.",
        "email_check_failed",
        duplicateError,
      );
    }
    if (duplicate) {
      reject(409, "That email address is already in use.", "email_in_use");
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
        mobile_number: mobileNumber,
        role,
        organization_id: targetOrganizationId,
        employment_category: role === "user" ? employmentCategory : "regular",
        contract_start_date: contract.start,
        contract_end_date: contract.end,
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
