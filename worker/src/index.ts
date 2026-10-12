const MODEL = "@cf/deepgram/nova-3";
const MAX_BODY_BYTES = 14 * 1024 * 1024;
const MAX_AUDIO_BYTES = 10 * 1024 * 1024;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

class APIError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) { super(message); }
}
function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...headers } });
}
function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
async function authenticate(request: Request, expected: string): Promise<void> {
  if (typeof expected !== "string" || expected.trim().length === 0) {
    throw new APIError(503, "NOT_CONFIGURED", "The transcription service is not configured.");
  }
  const match = /^Bearer ([^\s]+)$/i.exec(request.headers.get("Authorization") ?? "");
  const encoder = new TextEncoder();
  // Equal-length digests avoid leaking the configured secret's length during comparison.
  const [providedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(match?.[1] ?? "")),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  if (!crypto.subtle.timingSafeEqual(providedHash, expectedHash) || !match) {
    throw new APIError(401, "UNAUTHORIZED", "A valid bearer token is required.");
  }
}
async function readJSON(request: Request): Promise<unknown> {
  const contentType = request.headers.get("Content-Type")?.split(";", 1)[0].trim().toLowerCase();
  if (contentType !== "application/json") throw new APIError(415, "UNSUPPORTED_MEDIA_TYPE", "Send application/json.");
  const tooLarge = () => new APIError(413, "BODY_TOO_LARGE", "The request exceeds 14 MiB.");
  const declaredLength = request.headers.get("Content-Length");
  if (declaredLength && Number(declaredLength) > MAX_BODY_BYTES) throw tooLarge();
  if (!request.body) throw new APIError(400, "INVALID_JSON", "A JSON request body is required.");
  const reader = request.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false });
  const parts: string[] = [];
  let bytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > MAX_BODY_BYTES) {
        await reader.cancel();
        throw tooLarge();
      }
      parts.push(decoder.decode(value, { stream: true }));
    }
    parts.push(decoder.decode());
    return JSON.parse(parts.join("")) as unknown;
  } catch (error) {
    if (error instanceof APIError) throw error;
    await reader.cancel().catch(() => undefined);
    throw new APIError(400, "INVALID_JSON", "The body must be valid UTF-8 JSON.");
  } finally {
    reader.releaseLock();
  }
}
function decodeAudio(value: unknown): Uint8Array {
  if (typeof value !== "string" || value.length === 0 || value.length % 4 !== 0) {
    throw new APIError(400, "INVALID_AUDIO", "Audio must be a base64-encoded WAV file.");
  }
  const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
  if ((value.length / 4) * 3 - padding > MAX_AUDIO_BYTES) {
    throw new APIError(413, "AUDIO_TOO_LARGE", "Audio exceeds 10 MiB.");
  }
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(value)) throw new APIError(400, "INVALID_AUDIO", "Audio must use standard base64.");
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  // Reject nonzero unused bits (atob alone accepts noncanonical encodings).
  if (padding && (alphabet.indexOf(value[value.length - padding - 1]) & (padding === 2 ? 15 : 3)) !== 0) {
    throw new APIError(400, "INVALID_AUDIO", "Audio must use canonical base64.");
  }
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
function validateWAV(bytes: Uint8Array): void {
  const invalid = () => new APIError(400, "INVALID_WAV", "Use a complete 16-bit PCM WAV file (mono/stereo, 8–48 kHz).");
  if (bytes.length < 44) throw invalid();
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.getUint32(0) !== 0x52494646 || view.getUint32(8) !== 0x57415645 || view.getUint32(4, true) !== bytes.length - 8) throw invalid();
  let offset = 12;
  let format: { byteRate: number; blockAlign: number } | undefined;
  let dataLength: number | undefined;
  let chunks = 0;
  while (offset < bytes.length) {
    if (++chunks > 1024 || offset + 8 > bytes.length) throw invalid();
    const tag = view.getUint32(offset);
    const size = view.getUint32(offset + 4, true);
    const start = offset + 8;
    if (start + size > bytes.length) throw invalid();
    if (tag === 0x666d7420) {
      if (format || size < 16) throw invalid();
      const channels = view.getUint16(start + 2, true);
      const sampleRate = view.getUint32(start + 4, true);
      const byteRate = view.getUint32(start + 8, true);
      const blockAlign = view.getUint16(start + 12, true);
      if (view.getUint16(start, true) !== 1 || ![1, 2].includes(channels) || sampleRate < 8000 || sampleRate > 48000 ||
          view.getUint16(start + 14, true) !== 16 || blockAlign !== channels * 2 || byteRate !== sampleRate * blockAlign) throw invalid();
      format = { byteRate, blockAlign };
    } else if (tag === 0x64617461) {
      if (dataLength !== undefined) throw invalid();
      dataLength = size;
    }
    offset = start + size + (size % 2);
    if (offset > bytes.length) throw invalid();
  }
  if (!format || dataLength === undefined || dataLength % format.blockAlign !== 0) throw invalid();
  const duration = dataLength / format.byteRate;
  if (duration < 0.25) throw new APIError(400, "AUDIO_TOO_SHORT", "Record at least a quarter of a second.");
  if (duration > 300) throw new APIError(413, "AUDIO_TOO_LONG", "Recordings may not exceed five minutes.");
}
function hints(input: Record<string, unknown>): { language?: string; keyterm?: string; detect_language?: boolean } {
  const result: { language?: string; keyterm?: string; detect_language?: boolean } = {};
  if (input.language !== undefined) {
    if (typeof input.language !== "string") throw new APIError(400, "INVALID_LANGUAGE", "Language must be a language code or auto.");
    const language = input.language.trim().toLowerCase();
    if (language && language !== "auto") {
      if (!/^[a-z]{2,3}$/.test(language)) throw new APIError(400, "INVALID_LANGUAGE", "Use a two- or three-letter language code.");
      result.language = language;
    }
  }
  if (input.vocabulary !== undefined) {
    if (typeof input.vocabulary !== "string" || input.vocabulary.length > 1000) throw new APIError(400, "INVALID_VOCABULARY", "Vocabulary must be at most 1000 characters.");
    const vocabulary = input.vocabulary.trim();
    if (vocabulary) result.keyterm = vocabulary;
  }
  if (!result.language) result.detect_language = true;
  return result;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path !== "/health" && path !== "/v1/transcribe") return json({ error: { code: "NOT_FOUND", message: "Route not found." } }, 404);
    const method = path === "/health" ? "GET" : "POST";
    if (request.method !== method) return json({ error: { code: "METHOD_NOT_ALLOWED", message: `Use ${method}.` } }, 405, { Allow: method });
    if (path === "/health") return json({ service: "clearflow-dictation", model: MODEL });
    const started = Date.now();
    let requestId: string | undefined;
    try {
      await authenticate(request, env.AUTH_TOKEN);
      const { success } = await env.TRANSCRIBE_LIMITER.limit({ key: "clearflow-personal-transcription" });
      if (!success) throw new APIError(429, "RATE_LIMITED", "Too many requests. Try again in one minute.");
      const input = await readJSON(request);
      if (!isObject(input)) throw new APIError(400, "INVALID_REQUEST", "A JSON object is required.");
      if (typeof input.requestId !== "string" || !UUID.test(input.requestId)) throw new APIError(400, "INVALID_REQUEST_ID", "requestId must be a UUID.");
      requestId = input.requestId;
      const options = hints(input);
      const audio = decodeAudio(input.audio);
      validateWAV(audio);
      let prediction: unknown;
      try {
        prediction = await env.AI.run(MODEL, {
          audio: { body: new Response(audio).body!, contentType: "audio/wav" },
          punctuate: true, smart_format: true, ...options,
        });
      } catch {
        throw new APIError(502, "TRANSCRIPTION_FAILED", "Transcription failed. Please try again.");
      }
      const results = isObject(prediction) ? prediction.results : undefined;
      const channels = isObject(results) && Array.isArray(results.channels) ? results.channels : [];
      const channel = channels[0];
      const alternatives = isObject(channel) && Array.isArray(channel.alternatives) ? channel.alternatives : [];
      const alternative = alternatives[0];
      if (!isObject(alternative) || typeof alternative.transcript !== "string") {
        throw new APIError(502, "INVALID_MODEL_RESPONSE", "The speech model returned an invalid response.");
      }
      const text = alternative.transcript.trim();
      if (!text) throw new APIError(422, "NO_SPEECH", "No speech was detected. Try recording again.");
      return json({ text, requestId, model: MODEL, durationMs: Date.now() - started });
    } catch (error) {
      const failure = error instanceof APIError ? error : new APIError(503, "SERVICE_UNAVAILABLE", "The transcription service is temporarily unavailable.");
      // Never log the exception, headers, audio, vocabulary, or transcript.
      if (failure.status >= 500) console.error(JSON.stringify({ event: "transcription_failed", code: failure.code, requestId }));
      const headers: Record<string, string> = failure.status === 429 ? { "Retry-After": "60" } : failure.status === 401 ? { "WWW-Authenticate": "Bearer" } : {};
      return json({ error: { code: failure.code, message: failure.message }, ...(requestId ? { requestId } : {}) }, failure.status, headers);
    }
  },
} satisfies ExportedHandler<Env>;
