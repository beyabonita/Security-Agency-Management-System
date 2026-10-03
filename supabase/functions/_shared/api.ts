import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.112.3";

export type JsonObject = Record<string, unknown>;

export interface ApiContext {
  body: JsonObject;
  request: Request;
  requestId: string;
}

export interface ApiResult {
  data: JsonObject;
  status?: number;
}

const MAX_JSON_BODY_BYTES = 32 * 1024;
const DEFAULT_ALLOWED_ORIGINS = new Set([
  "https://security-agency-ms.vercel.app",
  "https://sams-it-portal.vercel.app",
  "https://sentinel-link-portal.vercel.app",
  "https://sentinel-link-system.vercel.app",
  "http://127.0.0.1:3000",
  "http://localhost:3000",
]);

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly publicMessage: string,
    readonly code: string,
    options?: { cause?: unknown },
  ) {
    super(publicMessage, options);
    this.name = "ApiError";
  }
}

export function reject(
  status: number,
  publicMessage: string,
  code: string,
): never {
  throw new ApiError(status, publicMessage, code);
}

export function backendFailure(
  publicMessage: string,
  code: string,
  cause: unknown,
  status = 500,
): never {
  throw new ApiError(status, publicMessage, code, { cause });
}

function configuredOrigins(): Set<string> {
  const allowed = new Set(DEFAULT_ALLOWED_ORIGINS);
  const configured = Deno.env.get("ALLOWED_WEB_ORIGINS") ?? "";
  for (const value of configured.split(",")) {
    const origin = value.trim();
    if (origin) allowed.add(origin);
  }
  return allowed;
}

function originAllowed(request: Request): boolean {
  const origin = request.headers.get("Origin");
  return origin === null || configuredOrigins().has(origin);
}

function requestIdFor(request: Request): string {
  const supplied = request.headers.get("X-Request-Id")?.trim() ?? "";
  return /^[A-Za-z0-9._:-]{1,100}$/.test(supplied)
    ? supplied
    : crypto.randomUUID();
}

function responseHeaders(request: Request, requestId: string): Headers {
  const headers = new Headers({
    "Cache-Control": "no-store",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Content-Type": "application/json; charset=utf-8",
    "Referrer-Policy": "no-referrer",
    "Vary": "Origin",
    "X-Content-Type-Options": "nosniff",
    "X-Request-Id": requestId,
  });
  const origin = request.headers.get("Origin");
  if (origin && configuredOrigins().has(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set(
      "Access-Control-Allow-Headers",
      "authorization, x-client-info, apikey, content-type, x-request-id",
    );
    headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    headers.set("Access-Control-Expose-Headers", "x-request-id");
    headers.set("Access-Control-Max-Age", "600");
  }
  return headers;
}

function jsonResponse(
  request: Request,
  requestId: string,
  data: JsonObject,
  status: number,
  extraHeaders?: Record<string, string>,
): Response {
  const headers = responseHeaders(request, requestId);
  for (const [key, value] of Object.entries(extraHeaders ?? {})) {
    headers.set(key, value);
  }
  return new Response(JSON.stringify({ ...data, requestId }), {
    status,
    headers,
  });
}

function errorForLog(error: unknown): JsonObject {
  if (error instanceof Error) {
    const cause = error.cause === undefined
      ? undefined
      : errorForLog(error.cause);
    return {
      name: error.name,
      message: error.message,
      ...(cause ? { cause } : {}),
    };
  }
  if (typeof error === "object" && error !== null) {
    const record = error as Record<string, unknown>;
    return Object.fromEntries(
      ["name", "message", "code", "status", "details", "hint"]
        .filter((key) => record[key] !== undefined)
        .map((key) => [key, String(record[key])]),
    );
  }
  return { value: String(error) };
}

export function logEvent(
  level: "info" | "warn" | "error",
  event: string,
  requestId: string,
  details: JsonObject = {},
): void {
  const entry = JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    event,
    requestId,
    ...details,
  });
  if (level === "error") console.error(entry);
  else if (level === "warn") console.warn(entry);
  else console.info(entry);
}

async function parseJsonBody(request: Request): Promise<JsonObject> {
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.toLowerCase().startsWith("application/json")) {
    reject(
      415,
      "Content-Type must be application/json.",
      "unsupported_media_type",
    );
  }

  const declaredLength = request.headers.get("Content-Length");
  if (declaredLength) {
    const bytes = Number(declaredLength);
    if (!Number.isFinite(bytes) || bytes < 0) {
      reject(400, "Invalid Content-Length header.", "invalid_content_length");
    }
    if (bytes > MAX_JSON_BODY_BYTES) {
      reject(413, "Request body is too large.", "request_too_large");
    }
  }

  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).byteLength > MAX_JSON_BODY_BYTES) {
    reject(413, "Request body is too large.", "request_too_large");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch (error) {
    throw new ApiError(400, "Invalid JSON request body.", "invalid_json", {
      cause: error,
    });
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    reject(400, "Request body must be a JSON object.", "invalid_request_body");
  }
  return parsed as JsonObject;
}

export async function handleJsonPost(
  request: Request,
  handler: (context: ApiContext) => ApiResult | Promise<ApiResult>,
): Promise<Response> {
  const requestId = requestIdFor(request);

  if (!originAllowed(request)) {
    return jsonResponse(
      request,
      requestId,
      { error: "This web origin is not allowed.", code: "origin_not_allowed" },
      403,
    );
  }
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: responseHeaders(request, requestId),
    });
  }
  if (request.method !== "POST") {
    return jsonResponse(
      request,
      requestId,
      { error: "Method not allowed.", code: "method_not_allowed" },
      405,
      { Allow: "POST, OPTIONS" },
    );
  }

  try {
    const body = await parseJsonBody(request);
    const result = await handler({ body, request, requestId });
    return jsonResponse(request, requestId, result.data, result.status ?? 200);
  } catch (error) {
    if (error instanceof ApiError) {
      if (error.status >= 500 || error.cause !== undefined) {
        logEvent("error", "api_request_failed", requestId, {
          code: error.code,
          status: error.status,
          error: errorForLog(error),
        });
      }
      return jsonResponse(
        request,
        requestId,
        { error: error.publicMessage, code: error.code },
        error.status,
      );
    }

    logEvent("error", "api_request_failed", requestId, {
      code: "internal_error",
      status: 500,
      error: errorForLog(error),
    });
    return jsonResponse(
      request,
      requestId,
      {
        error:
          "The service could not complete the request. Try again or contact support with the request ID.",
        code: "internal_error",
      },
      500,
    );
  }
}

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) {
    backendFailure(
      "The account service is not configured.",
      "service_configuration_error",
      new Error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing."),
    );
  }
  return createClient(url, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  });
}

export async function authenticatedUserId(
  request: Request,
  service: SupabaseClient,
): Promise<string> {
  const authHeader = request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(authHeader);
  if (!match) reject(401, "Unauthorized.", "unauthorized");

  const { data, error } = await service.auth.getUser(match[1]);
  if (error || !data.user) reject(401, "Unauthorized.", "unauthorized");
  return data.user.id;
}
