import { passwordError } from "../_shared/password-policy.ts";
import { personnelName } from "../_shared/personnel-name.ts";
import { philippineMobileNumber } from "../_shared/mobile-number.ts";
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
  authProviderMessage,
  beneficiaryOrganizationId,
  databaseBusinessMessage,
  emailValid,
  FIELD_ROLES,
  isAppRole,
  isEmploymentCategory,
  loadCallerProfile,
  type ManagedProfile,
  optionalBoolean,
  optionalString,
  PLATFORM_ROLES,
  uuidValid,
} from "../_shared/accounts.ts";

import { contractPeriod } from "../_shared/contract-period.ts";

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
        "Only IT Admin or Admin can manage accounts.",
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
    if (body.action !== "update" && body.action !== "remove") {
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
        "id,username,email,first_name,middle_initial,last_name,mobile_number,role,active,organization_id,employment_category,contract_start_date,contract_end_date,device_id,device_locked,removed_at",
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
      // A sole IT Admin can migrate their own email, without granting self role/access changes.
      const allowed = ["action", "userId", "email", "currentPassword"];
      if (
        !isItAdmin || body.email === undefined ||
        Object.keys(body).some((key) => !allowed.includes(key))
      ) {
        reject(
          400,
          "You can only change your own email here. Use another IT Admin to edit account access.",
          "self_management_blocked",
        );
      }
      if (typeof body.currentPassword !== "string" || !body.currentPassword) {
        reject(
          400,
          "Enter your current app password.",
          "current_password_required",
        );
      }
      const verifier = serviceClient();
      const { data: verified, error: verificationError } = await verifier.auth
        .signInWithPassword({
          email: target.email,
          password: body.currentPassword,
        });
      if (verified.session) await verifier.auth.signOut({ scope: "local" });
      if (verificationError || verified.user?.id !== callerId) {
        reject(
          403,
          "The current password is incorrect.",
          "password_verification_failed",
        );
      }
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
        "Admin can manage Guard and Inspector accounts in their own organization only.",
        "forbidden_target",
      );
    }
    if (
      isItAdmin &&
      !PLATFORM_ROLES.includes(target.role as "admin" | "it_admin")
    ) {
      reject(
        403,
        "IT Admin maintains IT and Admin access. Guard and Inspector accounts are managed by Admin.",
        "forbidden_target",
      );
    }

    if (body.action === 'remove') {
      if (!isHr || !FIELD_ROLES.includes(target.role as 'user' | 'inspector') || targetId === callerId) reject(403,'Only Operations Head can remove field personnel.','forbidden_target');
      const {error: removeError}=await service.from('profiles').update({active:false,removed_at:new Date().toISOString()}).eq('id',targetId);
      if(removeError)backendFailure('Could not remove personnel.','personnel_remove_failed',removeError);
      const {error: banError}=await service.auth.admin.updateUserById(targetId,{ban_duration:'876000h'});
      if(banError)backendFailure('Personnel access is disabled, but sign-in revocation needs a retry.','personnel_ban_failed',banError);
      return {data:{ok:true}};
    }
    if(targetData.removed_at)reject(409,'This personnel account has been removed.','personnel_removed');
    const requestedRole = body.role === undefined ? target.role : body.role;
    if (!isAppRole(requestedRole)) {
      reject(400, "Choose a valid account role.", "invalid_role");
    }
    if (isHr && requestedRole !== target.role) {
      reject(
        403,
        "Admin cannot change Guard and Inspector role types.",
        "forbidden_role",
      );
    }
    if (
      isItAdmin &&
      !PLATFORM_ROLES.includes(requestedRole as "admin" | "it_admin")
    ) {
      reject(
        403,
        "IT Admin may assign only IT Admin or Admin roles.",
        "forbidden_role",
      );
    }
    const role = requestedRole;

    const active = optionalBoolean(body, "active", "Active status") ??
      target.active;
    const resetDevice = optionalBoolean(body, "resetDevice", "Reset device") ??
      false;
    if (resetDevice && isItAdmin) {
      reject(
        403,
        "Device reset is available to Admin for personnel accounts only.",
        "forbidden_device_reset",
      );
    }
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

    const username = target.username;
    const requestedEmail = optionalString(body, "email", "Email", {
      max: 254,
      normalize: (value) => value.trim().toLowerCase(),
    });
    if (requestedEmail !== undefined && !emailValid(requestedEmail)) {
      reject(
        400,
        "Enter a valid email address, such as name@gmail.com.",
        "invalid_email",
      );
    }
    // Status/device updates must not require an email migration or recreate an alias.
    const authEmail = requestedEmail ?? target.email;
    const { data: duplicate, error: duplicateError } = await service.from(
      "profiles",
    )
      .select("id").eq("email", authEmail).neq("id", targetId).maybeSingle();
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

    let password = "";
    if (body.password !== undefined) {
      if (typeof body.password !== "string") {
        reject(400, "Password must be text.", "invalid_input");
      }
      password = body.password;
      const invalidPassword = password ? passwordError(password) : null;
      if (invalidPassword) {
        reject(
          400,
          invalidPassword,
          "invalid_input",
        );
      }
    }

    const firstName = optionalString(body, "firstName", "First name", {
      min: 1,
      max: 100,
      normalize: personnelName,
    }) ?? target.first_name;
    const middleName = optionalString(body, "middleName", "Middle name", {
      max: 100,
      normalize: (value) => value.trim(),
    }) ?? (body.middleName === null ? null : (target as Record<string, unknown>).middle_name as string | null | undefined);
    const middleInitial =
      optionalString(body, "middleInitial", "Middle initial", {
        max: 10,
        normalize: personnelName,
      }) ?? (middleName ? middleName.charAt(0).toUpperCase() : target.middle_initial);
    const lastName = optionalString(body, "lastName", "Last name", {
      min: 1,
      max: 100,
      normalize: personnelName,
    }) ?? target.last_name;

    const personnelId = optionalString(body, "personnelId", "Personnel ID", {
      max: 100,
      normalize: (value) => value.trim(),
    }) ?? (body.personnelId === null ? null : (target as Record<string, unknown>).personnel_id as string | null | undefined);
    const dateOfBirth = optionalString(body, "dateOfBirth", "Date of birth") ??
      (body.dateOfBirth === null ? null : (target as Record<string, unknown>).date_of_birth as string | null | undefined);
    const gender = optionalString(body, "gender", "Gender", { max: 50 }) ??
      (body.gender === null ? null : (target as Record<string, unknown>).gender as string | null | undefined);
    const civilStatus = optionalString(body, "civilStatus", "Civil status", { max: 50 }) ??
      (body.civilStatus === null ? null : (target as Record<string, unknown>).civil_status as string | null | undefined);
    const completeAddress = optionalString(body, "completeAddress", "Complete address", {
      max: 500,
      normalize: (value) => value.trim(),
    }) ?? (body.completeAddress === null ? null : (target as Record<string, unknown>).complete_address as string | null | undefined);
    const dateHired = optionalString(body, "dateHired", "Date hired") ??
      (body.dateHired === null ? null : (target as Record<string, unknown>).date_hired as string | null | undefined);
    const contractStatus = optionalString(body, "contractStatus", "Contract status", { max: 50 }) ??
      (body.contractStatus === null ? null : (target as Record<string, unknown>).contract_status as string | null | undefined);
    const licenseSecurityUrl = typeof body.licenseSecurityUrl === "string" ? body.licenseSecurityUrl :
      (body.licenseSecurityUrl === null ? null : (target as Record<string, unknown>).license_security_url as string | null | undefined);
    const licenseFirearmsUrl = typeof body.licenseFirearmsUrl === "string" ? body.licenseFirearmsUrl :
      (body.licenseFirearmsUrl === null ? null : (target as Record<string, unknown>).license_firearms_url as string | null | undefined);

    const mobileNumber = body.mobileNumber === undefined ? target.mobile_number ?? null
      : philippineMobileNumber(body.mobileNumber);
    const employmentValue = body.employmentCategory === undefined
      ? target.employment_category
      : body.employmentCategory;
    if (!isEmploymentCategory(employmentValue)) {
      reject(400, "Choose Regular or Contract duty.", "invalid_duty_category");
    }
    const employmentCategory = role === "user" ? employmentValue : "regular";
    const contract = contractPeriod(
      employmentCategory,
      body.contractStartDate === undefined
        ? target.contract_start_date
        : body.contractStartDate,
      body.contractEndDate === undefined
        ? target.contract_end_date
        : body.contractEndDate,
      body.employmentCategory === undefined &&
        body.contractStartDate === undefined &&
        body.contractEndDate === undefined,
    );
    if (contract.error) reject(400, contract.error, "invalid_contract_period");

    let organizationId: string | null = isHr ? caller.organization_id : null;
    if (isItAdmin && role === "admin") {
      organizationId = await beneficiaryOrganizationId(service);
    }

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
      mobile_number: target.mobile_number ?? null,
      last_name: target.last_name,
      role: target.role,
      active: target.active,
      organization_id: target.organization_id,
      employment_category: target.employment_category,
      contract_start_date: target.contract_start_date,
      contract_end_date: target.contract_end_date,
      device_id: target.device_id,
      device_locked: target.device_locked,
    };
    const profileUpdate: Record<string, unknown> = {
      username,
      email: authEmail,
      first_name: firstName,
      middle_initial: middleInitial,
      mobile_number: mobileNumber,
      last_name: lastName,
      role,
      active,
      organization_id: organizationId,
      employment_category: employmentCategory,
      contract_start_date: contract.start,
      contract_end_date: contract.end,
      ...(resetDevice ? { device_id: null, device_locked: false } : {}),
      ...(middleName !== undefined ? { middle_name: middleName } : {}),
      ...(personnelId !== undefined ? { personnel_id: personnelId } : {}),
      ...(dateOfBirth !== undefined ? { date_of_birth: dateOfBirth } : {}),
      ...(gender !== undefined ? { gender } : {}),
      ...(civilStatus !== undefined ? { civil_status: civilStatus } : {}),
      ...(completeAddress !== undefined ? { complete_address: completeAddress } : {}),
      ...(dateHired !== undefined ? { date_hired: dateHired } : {}),
      ...(contractStatus !== undefined ? { contract_status: contractStatus } : {}),
      ...(licenseSecurityUrl !== undefined ? { license_security_url: licenseSecurityUrl } : {}),
      ...(licenseFirearmsUrl !== undefined ? { license_firearms_url: licenseFirearmsUrl } : {}),
    };
    let { data: updatedProfile, error: profileError } = await service
      .from("profiles")
      .update(profileUpdate)
      .eq("id", targetId)
      .select("id")
      .maybeSingle();

    if (profileError && (profileError as { code?: string })?.code === "42703") {
      const fallback = await service
        .from("profiles")
        .update({
          username,
          email: authEmail,
          first_name: firstName,
          middle_initial: middleInitial,
          mobile_number: mobileNumber,
          last_name: lastName,
          role,
          active,
          organization_id: organizationId,
          employment_category: employmentCategory,
          contract_start_date: contract.start,
          contract_end_date: contract.end,
          ...(resetDevice ? { device_id: null, device_locked: false } : {}),
        })
        .eq("id", targetId)
        .select("id")
        .maybeSingle();
      updatedProfile = fallback.data;
      profileError = fallback.error;
    }

    if (role === "user" && employmentCategory === "contract" && contract.start && contract.end) {
      try {
        await service.from("guard_contract_history").insert({
          guard_id: targetId,
          contract_start_date: contract.start,
          contract_end_date: contract.end,
          contract_status: contractStatus || "Active",
          renewed_at: new Date().toISOString(),
          renewed_by: callerId,
          remarks: "Contract updated via personnel account management",
        });
      } catch (_) {
        // history recording is best effort
      }
    }
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
      ...(requestedEmail !== undefined ? { email_confirm: true } : {}),
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
