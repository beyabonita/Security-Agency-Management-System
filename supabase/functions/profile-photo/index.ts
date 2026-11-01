import {
  ApiError,
  authenticatedUserId,
  backendFailure,
  logEvent,
  reject,
  serviceClient,
} from "../_shared/api.ts";
import {
  FIELD_ROLES,
  isAppRole,
  loadCallerProfile,
  uuidValid,
} from "../_shared/accounts.ts";

const MAX_PHOTO_BYTES = 2 * 1024 * 1024; // 2 MB binary limit
const MAX_REQUEST_BYTES = Math.ceil(MAX_PHOTO_BYTES * 1.45) + 32 * 1024; // allows 2 MB base64 JSON envelope
const BUCKET_ID = "profile-photos";

const ALLOWED_BODY_KEYS = new Set([
  "action",
  "targetUserId",
  "userId",
  "photoBase64",
  "mimeType",
  "fileName",
  "file",
]);

function isAllowedOrigin(origin: string | null): boolean {
  if (!origin || origin === "null") return true;
  if (/^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?$/.test(origin)) {
    return true;
  }
  if (/^https:\/\/[a-z0-9-]+(\.vercel\.app)$/i.test(origin)) return true;
  if (
    /^https?:\/\/(www\.)?tts-agency\.site$/i.test(origin) ||
    /\.tts-agency\.site$/i.test(origin)
  ) {
    return true;
  }
  const configured = (Deno.env.get("ALLOWED_WEB_ORIGINS") ?? "")
    .split(",")
    .map((v) => v.trim())
    .filter(Boolean);
  return configured.includes(origin);
}

function buildHeaders(request: Request, requestId: string): Headers {
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
  if (origin && isAllowedOrigin(origin)) {
    headers.set(
      "Access-Control-Allow-Origin",
      origin === "null" ? "*" : origin,
    );
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

function respondJson(
  request: Request,
  requestId: string,
  payload: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify({ ...payload, requestId }), {
    status,
    headers: buildHeaders(request, requestId),
  });
}

function decodeBase64Photo(raw: string): Uint8Array {
  const trimmed = raw.trim();
  const commaIdx = trimmed.indexOf(",");
  const base64Part = trimmed.startsWith("data:") && commaIdx !== -1
    ? trimmed.slice(commaIdx + 1)
    : trimmed;
  const normalized = base64Part.replace(/\s+/g, "");
  try {
    const bin = atob(normalized);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) {
      out[i] = bin.charCodeAt(i);
    }
    return out;
  } catch {
    reject(400, "Invalid base64 image payload.", "invalid_image_encoding");
  }
}

function detectMagicType(
  bytes: Uint8Array,
): { mime: "image/jpeg" | "image/png"; ext: "jpg" | "png" } {
  if (
    bytes.length >= 4 &&
    bytes[0] === 0xFF &&
    bytes[1] === 0xD8 &&
    bytes[2] === 0xFF
  ) {
    return { mime: "image/jpeg", ext: "jpg" };
  }
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4E &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0D &&
    bytes[5] === 0x0A &&
    bytes[6] === 0x1A &&
    bytes[7] === 0x0A
  ) {
    return { mime: "image/png", ext: "png" };
  }
  reject(
    400,
    "Only JPG and PNG images are allowed.",
    "invalid_file_type",
  );
}

/**
 * Strips EXIF, GPS, XMP, IPTC (APP1..APP13, APP15) and COM segments from a JPEG
 * while validating marker segment framing and dimensions.
 */
function stripJpegMetadata(bytes: Uint8Array): Uint8Array {
  if (bytes.length < 4 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) {
    reject(400, "Invalid JPEG file header.", "corrupt_image");
  }

  const chunks: Uint8Array[] = [new Uint8Array([0xFF, 0xD8])];
  let offset = 2;
  let sawSof = false;
  let sawSos = false;

  while (offset < bytes.length) {
    if (bytes[offset] !== 0xFF) {
      reject(400, "Malformed JPEG segment structure.", "corrupt_image");
    }
    while (offset < bytes.length && bytes[offset] === 0xFF) {
      offset++;
    }
    if (offset >= bytes.length) break;

    const marker = bytes[offset++];
    if (marker === 0x00 || marker === 0xD8) {
      reject(400, "Unexpected JPEG marker.", "corrupt_image");
    }
    if (marker === 0xD9) {
      // Premature EOI before scan data
      if (!sawSos) {
        reject(400, "Incomplete JPEG image data.", "corrupt_image");
      }
      chunks.push(new Uint8Array([0xFF, 0xD9]));
      break;
    }

    // Standalone markers without payload length (RST0..RST7, TEM)
    if ((marker >= 0xD0 && marker <= 0xD7) || marker === 0x01) {
      chunks.push(new Uint8Array([0xFF, marker]));
      continue;
    }

    if (offset + 2 > bytes.length) {
      reject(400, "Truncated JPEG marker header.", "corrupt_image");
    }
    const segLen = (bytes[offset] << 8) | bytes[offset + 1];
    if (segLen < 2 || offset + segLen > bytes.length) {
      reject(400, "Truncated JPEG segment payload.", "corrupt_image");
    }

    // Start of Scan (0xDA): copy SOS header + entropy-coded scan data through EOI
    if (marker === 0xDA) {
      if (!sawSof) {
        reject(400, "JPEG is missing frame header.", "corrupt_image");
      }
      sawSos = true;
      // Verify trailing EOI exists or trim trailing junk after final FF D9
      let endIdx = bytes.length;
      for (let i = bytes.length - 2; i >= offset + segLen; i--) {
        if (bytes[i] === 0xFF && bytes[i + 1] === 0xD9) {
          endIdx = i + 2;
          break;
        }
      }
      const sosStart = offset - 2;
      // Ensure normalized 0xFF 0xDA prefix in case of multi-0xFF padding
      const headerAndScan = new Uint8Array(2 + (endIdx - offset));
      headerAndScan[0] = 0xFF;
      headerAndScan[1] = 0xDA;
      headerAndScan.set(bytes.subarray(offset, endIdx), 2);
      chunks.push(headerAndScan);
      if (
        endIdx < 2 ||
        bytes[endIdx - 2] !== 0xFF ||
        bytes[endIdx - 1] !== 0xD9
      ) {
        chunks.push(new Uint8Array([0xFF, 0xD9]));
      }
      break;
    }

    // SOFn frame markers (validate sensible image dimensions <= 4096)
    if (
      marker >= 0xC0 &&
      marker <= 0xCF &&
      marker !== 0xC4 &&
      marker !== 0xC8 &&
      marker !== 0xCC
    ) {
      if (segLen < 7) {
        reject(400, "Invalid JPEG frame dimensions.", "corrupt_image");
      }
      const height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      const width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width <= 0 || height <= 0 || width > 4096 || height > 4096) {
        reject(
          400,
          "Profile photo dimensions must be between 1x1 and 4096x4096.",
          "invalid_dimensions",
        );
      }
      sawSof = true;
    }

    // Strip metadata segments: APP1..APP13 (0xE1..0xED), APP15 (0xEF), and COM (0xFE)
    const isMetadataSegment =
      (marker >= 0xE1 && marker <= 0xED) ||
      marker === 0xEF ||
      marker === 0xFE;

    if (!isMetadataSegment) {
      const seg = new Uint8Array(2 + segLen);
      seg[0] = 0xFF;
      seg[1] = marker;
      seg.set(bytes.subarray(offset, offset + segLen), 2);
      chunks.push(seg);
    }

    offset += segLen;
  }

  if (!sawSos) {
    reject(400, "Invalid or incomplete JPEG image.", "corrupt_image");
  }

  const totalLength = chunks.reduce((sum, part) => sum + part.length, 0);
  const cleaned = new Uint8Array(totalLength);
  let cursor = 0;
  for (const part of chunks) {
    cleaned.set(part, cursor);
    cursor += part.length;
  }
  return cleaned;
}

const SAFE_PNG_CHUNKS = new Set([
  "IHDR",
  "PLTE",
  "tRNS",
  "gAMA",
  "cHRM",
  "sRGB",
  "sBIT",
  "bKGD",
  "pHYs",
  "IDAT",
  "IEND",
]);

/**
 * Strips eXIf, tEXt, zTXt, iTXt, tIME, iCCP and private metadata chunks from a PNG
 * while validating chunk framing, IHDR dimensions, IDAT presence, and IEND termination.
 */
function stripPngMetadata(bytes: Uint8Array): Uint8Array {
  const pngSig = new Uint8Array([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);
  if (bytes.length < 33) {
    reject(400, "Invalid PNG image.", "corrupt_image");
  }

  const chunks: Uint8Array[] = [pngSig];
  let offset = 8;
  let sawIhdr = false;
  let sawIdat = false;
  let sawIend = false;

  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) {
      reject(400, "Truncated PNG chunk header.", "corrupt_image");
    }
    const view = new DataView(
      bytes.buffer,
      bytes.byteOffset + offset,
      bytes.byteLength - offset,
    );
    const dataLen = view.getUint32(0, false);
    const totalChunkBytes = 12 + dataLen;
    if (dataLen > MAX_PHOTO_BYTES || offset + totalChunkBytes > bytes.length) {
      reject(400, "Corrupted PNG chunk length.", "corrupt_image");
    }

    const type = String.fromCharCode(
      bytes[offset + 4],
      bytes[offset + 5],
      bytes[offset + 6],
      bytes[offset + 7],
    );

    if (!sawIhdr && type !== "IHDR") {
      reject(400, "PNG must begin with IHDR.", "corrupt_image");
    }
    if (type === "IHDR") {
      if (dataLen !== 13) {
        reject(400, "Invalid PNG IHDR length.", "corrupt_image");
      }
      const width = view.getUint32(8, false);
      const height = view.getUint32(12, false);
      if (width <= 0 || height <= 0 || width > 4096 || height > 4096) {
        reject(
          400,
          "Profile photo dimensions must be between 1x1 and 4096x4096.",
          "invalid_dimensions",
        );
      }
      sawIhdr = true;
    }
    if (type === "IDAT") sawIdat = true;

    if (SAFE_PNG_CHUNKS.has(type)) {
      chunks.push(bytes.subarray(offset, offset + totalChunkBytes));
    }

    offset += totalChunkBytes;
    if (type === "IEND") {
      sawIend = true;
      break;
    }
  }

  if (!sawIhdr || !sawIdat || !sawIend) {
    reject(400, "Incomplete or corrupted PNG image.", "corrupt_image");
  }

  const totalLength = chunks.reduce((sum, part) => sum + part.length, 0);
  const cleaned = new Uint8Array(totalLength);
  let cursor = 0;
  for (const part of chunks) {
    cleaned.set(part, cursor);
    cursor += part.length;
  }
  return cleaned;
}

Deno.serve(async (request: Request): Promise<Response> => {
  const suppliedId = request.headers.get("X-Request-Id")?.trim() ?? "";
  const requestId = /^[A-Za-z0-9._:-]{1,100}$/.test(suppliedId)
    ? suppliedId
    : crypto.randomUUID();

  if (!isAllowedOrigin(request.headers.get("Origin"))) {
    return respondJson(
      request,
      requestId,
      { error: "This web origin is not allowed.", code: "origin_not_allowed" },
      403,
    );
  }

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: buildHeaders(request, requestId),
    });
  }

  if (request.method !== "POST") {
    return respondJson(
      request,
      requestId,
      { error: "Method not allowed.", code: "method_not_allowed" },
      405,
    );
  }

  try {
    const service = serviceClient();
    const callerId = await authenticatedUserId(request, service);
    const caller = await loadCallerProfile(service, callerId);

    if (!caller.active) {
      reject(403, "Your account is inactive.", "forbidden");
    }

    const contentType = (request.headers.get("Content-Type") ?? "")
      .toLowerCase();
    let action = "upload";
    let requestedTargetId: string | null = null;
    let rawBytes: Uint8Array | null = null;

    if (contentType.startsWith("multipart/form-data")) {
      const form = await request.formData();
      for (const key of form.keys()) {
        if (!ALLOWED_BODY_KEYS.has(key)) {
          reject(
            403,
            `Field "${key}" is read-only and cannot be modified here.`,
            "locked_field_rejected",
          );
        }
      }
      const actionVal = form.get("action");
      if (typeof actionVal === "string" && actionVal.trim()) {
        action = actionVal.trim().toLowerCase();
      }
      const targetVal = form.get("targetUserId") ?? form.get("userId");
      if (typeof targetVal === "string" && targetVal.trim()) {
        requestedTargetId = targetVal.trim();
      }
      const filePart = form.get("file");
      if (action === "upload") {
        if (!(filePart instanceof File)) {
          reject(400, "Select a JPG or PNG photo to upload.", "missing_photo");
        }
        if (filePart.size > MAX_PHOTO_BYTES) {
          reject(
            413,
            "Profile photo must be 2 MB or smaller.",
            "photo_too_large",
          );
        }
        rawBytes = new Uint8Array(await filePart.arrayBuffer());
      }
    } else if (contentType.startsWith("application/json")) {
      const text = await request.text();
      if (new TextEncoder().encode(text).byteLength > MAX_REQUEST_BYTES) {
        reject(
          413,
          "Profile photo must be 2 MB or smaller.",
          "photo_too_large",
        );
      }
      let body: Record<string, unknown>;
      try {
        const parsed = JSON.parse(text);
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
          throw new Error("Expected object");
        }
        body = parsed as Record<string, unknown>;
      } catch {
        reject(400, "Invalid JSON request body.", "invalid_json");
      }

      for (const key of Object.keys(body)) {
        if (!ALLOWED_BODY_KEYS.has(key)) {
          reject(
            403,
            `Field "${key}" is read-only and cannot be modified here.`,
            "locked_field_rejected",
          );
        }
      }

      if (typeof body.action === "string" && body.action.trim()) {
        action = body.action.trim().toLowerCase();
      }
      const rawTarget = body.targetUserId ?? body.userId;
      if (typeof rawTarget === "string" && rawTarget.trim()) {
        requestedTargetId = rawTarget.trim();
      }
      if (action === "upload") {
        if (typeof body.photoBase64 !== "string" || !body.photoBase64.trim()) {
          reject(400, "Select a JPG or PNG photo to upload.", "missing_photo");
        }
        rawBytes = decodeBase64Photo(body.photoBase64);
      }
    } else {
      reject(
        415,
        "Content-Type must be application/json or multipart/form-data.",
        "unsupported_media_type",
      );
    }

    if (action !== "upload" && action !== "remove") {
      reject(
        400,
        'Invalid action. Expected "upload" or "remove".',
        "invalid_action",
      );
    }

    const targetId = requestedTargetId ?? callerId;
    if (!uuidValid(targetId)) {
      reject(400, "Invalid personnel account ID.", "invalid_account_id");
    }

    // Role-based access enforcement
    if (caller.role === "user") {
      if (targetId !== callerId) {
        reject(
          403,
          "Guards can only customize their own profile photo.",
          "forbidden_target",
        );
      }
    } else if (caller.role === "admin") {
      if (!caller.organization_id) {
        reject(403, "Admin organization is not configured.", "forbidden");
      }
      if (targetId !== callerId) {
        const { data: targetRow, error: targetErr } = await service
          .from("profiles")
          .select("id, role, organization_id")
          .eq("id", targetId)
          .maybeSingle();
        if (targetErr) {
          backendFailure(
            "Could not verify personnel profile.",
            "target_lookup_failed",
            targetErr,
          );
        }
        if (!targetRow || !isAppRole(targetRow.role)) {
          reject(404, "Personnel profile not found.", "account_not_found");
        }
        if (
          targetRow.organization_id !== caller.organization_id ||
          !FIELD_ROLES.includes(targetRow.role as "user" | "inspector")
        ) {
          reject(
            403,
            "Operations Head can only manage photos for personnel in their organization.",
            "forbidden_target",
          );
        }
      }
    } else if (caller.role !== "it_admin") {
      reject(
        403,
        "You do not have permission to update this profile photo.",
        "forbidden",
      );
    }

    if (action === "remove") {
      await service.storage
        .from(BUCKET_ID)
        .remove([`${targetId}/avatar.jpg`, `${targetId}/avatar.png`])
        .catch(() => {});

      const { error: clearErr } = await service
        .from("profiles")
        .update({ profile_photo_url: null })
        .eq("id", targetId);

      if (clearErr) {
        backendFailure(
          "Could not clear profile photo URL.",
          "photo_clear_failed",
          clearErr,
        );
      }

      logEvent("info", "profile_photo_removed", requestId, {
        actorId: callerId,
        targetId,
      });

      return respondJson(request, requestId, {
        ok: true,
        profilePhotoUrl: null,
      });
    }

    // Upload / Replace flow
    if (!rawBytes || rawBytes.byteLength === 0) {
      reject(400, "Uploaded image file is empty.", "empty_photo");
    }
    if (rawBytes.byteLength > MAX_PHOTO_BYTES) {
      reject(
        413,
        "Profile photo must be 2 MB or smaller.",
        "photo_too_large",
      );
    }

    const detected = detectMagicType(rawBytes);
    const strippedBytes = detected.ext === "jpg"
      ? stripJpegMetadata(rawBytes)
      : stripPngMetadata(rawBytes);

    const objectPath = `${targetId}/avatar.${detected.ext}`;
    const stalePath = detected.ext === "jpg"
      ? `${targetId}/avatar.png`
      : `${targetId}/avatar.jpg`;

    const { error: uploadErr } = await service.storage
      .from(BUCKET_ID)
      .upload(objectPath, strippedBytes, {
        contentType: detected.mime,
        cacheControl: "3600",
        upsert: true,
      });

    if (uploadErr) {
      backendFailure(
        "Could not store profile photo.",
        "storage_upload_failed",
        uploadErr,
      );
    }

    // Clean up opposite extension if previously uploaded
    await service.storage.from(BUCKET_ID).remove([stalePath]).catch(() => {});

    const { data: pub } = service.storage
      .from(BUCKET_ID)
      .getPublicUrl(objectPath);
    const versionedUrl = `${pub.publicUrl}?v=${Date.now()}`;

    const { error: updateErr } = await service
      .from("profiles")
      .update({ profile_photo_url: versionedUrl })
      .eq("id", targetId);

    if (updateErr) {
      backendFailure(
        "Could not save profile photo URL.",
        "profile_photo_update_failed",
        updateErr,
      );
    }

    logEvent("info", "profile_photo_updated", requestId, {
      actorId: callerId,
      targetId,
      mime: detected.mime,
      originalBytes: rawBytes.byteLength,
      strippedBytes: strippedBytes.byteLength,
    });

    return respondJson(request, requestId, {
      ok: true,
      profilePhotoUrl: versionedUrl,
    });
  } catch (error) {
    if (error instanceof ApiError) {
      return respondJson(
        request,
        requestId,
        { error: error.publicMessage, code: error.code },
        error.status,
      );
    }
    logEvent("error", "profile_photo_unhandled_error", requestId, {
      message: error instanceof Error ? error.message : String(error),
    });
    return respondJson(
      request,
      requestId,
      {
        error: "Could not process profile photo. Please try again.",
        code: "internal_error",
      },
      500,
    );
  }
});

