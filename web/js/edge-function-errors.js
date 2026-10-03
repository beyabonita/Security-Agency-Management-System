(function (root) {
  'use strict';

  const REQUEST_ID_PATTERN = /^[A-Za-z0-9._:-]{1,100}$/;
  const HTTP_ERROR_PLACEHOLDER = /^Edge Function returned a non-2xx status code\.?$/i;

  function cleanText(value) {
    return typeof value === 'string' ? value.trim() : '';
  }

  function cleanRequestId(value) {
    const candidate = cleanText(value);
    return REQUEST_ID_PATTERN.test(candidate) ? candidate : '';
  }

  function objectPayload(value) {
    return value && typeof value === 'object' && !Array.isArray(value) ? value : null;
  }

  async function readHttpErrorContext(context) {
    if (!context || typeof context !== 'object') return { payload: null, requestId: '' };

    let requestId = '';
    try {
      requestId = cleanRequestId(context.headers?.get?.('x-request-id'));
    } catch (_) {}

    let payload = null;
    try {
      const readable = typeof context.clone === 'function' ? context.clone() : context;
      if (typeof readable?.json === 'function') payload = objectPayload(await readable.json());
    } catch (_) {}

    return {
      payload,
      requestId: cleanRequestId(payload?.requestId) || requestId,
    };
  }

  async function describe(result, fallback) {
    const fallbackMessage = cleanText(fallback) || 'The request could not be completed. Please try again.';
    const resultPayload = objectPayload(result?.data);
    const context = await readHttpErrorContext(result?.error?.context);
    const sdkMessage = cleanText(result?.error?.message);
    const message = cleanText(context.payload?.error)
      || cleanText(resultPayload?.error)
      || (HTTP_ERROR_PLACEHOLDER.test(sdkMessage) ? '' : sdkMessage)
      || fallbackMessage;
    const requestId = context.requestId || cleanRequestId(resultPayload?.requestId);
    return requestId && !message.includes(requestId)
      ? `${message} (Request ID: ${requestId})`
      : message;
  }

  async function unwrap(result, fallback) {
    const resultPayload = objectPayload(result?.data);
    if (result && !result.error && !cleanText(resultPayload?.error)) return result.data;
    throw new Error(await describe(result, fallback));
  }

  const api = Object.freeze({ describe, unwrap });
  if (root) root.edgeFunctionErrors = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
