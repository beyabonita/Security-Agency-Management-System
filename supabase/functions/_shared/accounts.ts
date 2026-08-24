import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.112.3";
import { backendFailure, type JsonObject, reject } from "./api.ts";

export const AUTH_EMAIL_DOMAIN = "asamanion-26858.auth";
export const BENEFICIARY_SLUG = "twentytwenty-security-agency";
export const APP_ROLES = ["user", "inspector", "admin", "it_admin"] as const;
export const FIELD_ROLES = ["user", "inspector"] as const;
export const PLATFORM_ROLES = ["admin", "it_admin"] as const;
export const EMPLOYMENT_CATEGORIES = ["regular", "contract"] as const;

export type AppRole = typeof APP_ROLES[number];
export type EmploymentCategory = typeof EMPLOYMENT_CATEGORIES[number];

export interface CallerProfile {
  active: boolean;
  organization_id: string | null;
  role: AppRole;
}

export interface ManagedProfile extends CallerProfile {
  device_id: string | null;
  device_locked: boolean;
  email: string;
  employment_category: EmploymentCategory;
  first_name: string;
  id: string;
  last_name: string;
  middle_initial: string;
  username: string;
}

export function isAppRole(value: unknown): value is AppRole {
  return typeof value === "string" && APP_ROLES.includes(value as AppRole);
}

export function isEmploymentCategory(
  value: unknown,
): value is EmploymentCategory {
  return typeof value === "string" && EMPLOYMENT_CATEGORIES.includes(
    value as EmploymentCategory,
  );
}

export function usernameValid(value: string): boolean {
  return /^[a-z0-9._]{3,32}$/.test(value);
}

export function uuidValid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

export function optionalString(
  body: JsonObject,
  key: string,
  label: string,
  options: { max: number; min?: number; normalize?: (value: string) => string },
): string | undefined {
  if (body[key] === undefined) return undefined;
  if (typeof body[key] !== "string") {
    reject(400, `${label} must be text.`, "invalid_input");
  }
  const value = options.normalize
    ? options.normalize(body[key] as string)
    : (body[key] as string);
  if (value.includes("\u0000")) {
    reject(400, `${label} contains invalid characters.`, "invalid_input");
  }
  if (value.length < (options.min ?? 0) || value.length > options.max) {
    const range = options.min
      ? `${options.min} to ${options.max}`
      : `at most ${options.max}`;
    reject(400, `${label} must contain ${range} characters.`, "invalid_input");
  }
  return value;
}

export function optionalBoolean(
  body: JsonObject,
  key: string,
  label: string,
): boolean | undefined {
  if (body[key] === undefined) return undefined;
  if (typeof body[key] !== "boolean") {
    reject(400, `${label} must be true or false.`, "invalid_input");
  }
  return body[key] as boolean;
}

export async function loadCallerProfile(
  service: SupabaseClient,
  userId: string,
): Promise<CallerProfile> {
  const { data, error } = await service
    .from("profiles")
    .select("role,organization_id,active")
    .eq("id", userId)
    .maybeSingle();
  if (error) {
    backendFailure(
      "The account permission check could not be completed.",
      "profile_lookup_failed",
      error,
    );
  }
  if (!data || !isAppRole(data.role)) {
    reject(403, "Your account does not have management access.", "forbidden");
  }
  return data as CallerProfile;
}

export async function beneficiaryOrganizationId(
  service: SupabaseClient,
): Promise<string> {
  const { data, error } = await service
    .from("organizations")
    .select("id,active")
    .eq("slug", BENEFICIARY_SLUG)
    .maybeSingle();
  if (error) {
    backendFailure(
      "The beneficiary configuration could not be loaded.",
      "beneficiary_lookup_failed",
      error,
    );
  }
  if (!data?.active) {
    reject(
      409,
      "TwentyTwenty Security Agency is not configured as the active beneficiary yet.",
      "beneficiary_not_configured",
    );
  }
  return String(data.id);
}

export function authProviderMessage(error: unknown): string {
  const message = error instanceof Error
    ? error.message
    : typeof error === "object" && error !== null && "message" in error
    ? String((error as { message?: unknown }).message ?? "")
    : String(error ?? "");
  const normalized = message.toLowerCase();
  if (
    normalized.includes("already") ||
    normalized.includes("registered") ||
    normalized.includes("duplicate")
  ) {
    return "That username is already in use.";
  }
  if (normalized.includes("password")) {
    return "The password does not meet the authentication requirements.";
  }
  return "The authentication account could not be processed. Check the details and try again.";
}

export function databaseBusinessMessage(
  error: unknown,
): string | undefined {
  const code = typeof error === "object" && error !== null && "code" in error
    ? String((error as { code?: unknown }).code ?? "")
    : "";
  const message =
    typeof error === "object" && error !== null && "message" in error
      ? String((error as { message?: unknown }).message ?? "")
      : "";
  const allowedMessages = [
    "Reassign or clear all Guard Inspector assignments before disabling, moving, or changing this Inspector.",
    "The last active IT Admin must remain active and keep the IT Admin role.",
  ];
  if (code === "23505" && message.toLowerCase().includes("username")) {
    return "That username is already in use.";
  }
  return allowedMessages.find((allowed) => message.includes(allowed));
}
