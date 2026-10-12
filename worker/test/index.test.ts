import { env } from "cloudflare:workers";
import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";

const requestId = "5c30d667-8f4e-4b0d-a644-a25d93ccbf03";
const nova = (transcript: string) => ({ results: { channels: [{ alternatives: [{ transcript }] }] } });
const maxBody = 14 * 1024 * 1024;
function wav(seconds = 1): Uint8Array {
  const size = Math.floor(seconds * 16000) * 2;
  const result = new Uint8Array(44 + size);
  const view = new DataView(result.buffer);
  const tag = (offset: number, value: string) => result.set(new TextEncoder().encode(value), offset);
  tag(0, "RIFF"); view.setUint32(4, result.length - 8, true); tag(8, "WAVE");
  tag(12, "fmt "); view.setUint32(16, 16, true); view.setUint16(20, 1, true);
  view.setUint16(22, 1, true); view.setUint32(24, 16000, true); view.setUint32(28, 32000, true);
  view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  tag(36, "data"); view.setUint32(40, size, true);
  return result;
}
function base64(bytes: Uint8Array): string {
  let encoded = "";
  for (let i = 0; i < bytes.length; i += 8192) encoded += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(encoded);
}
function payload(extra: Record<string, unknown> = {}) { return { requestId, audio: base64(wav()), ...extra }; }
function request(value: unknown = payload(), headers: Record<string, string> = {}): Request {
  return new Request("https://clearflow.test/v1/transcribe", { method: "POST", headers: {
    "Authorization": "Bearer test-only-token", "Content-Type": "application/json", ...headers,
  }, body: JSON.stringify(value) });
}
async function result(req = request(), bindings: Env = env) {
  const response = await worker.fetch(req, bindings);
  const body = await response.json<Record<string, any>>();
  return { response, body };
}
let ai: ReturnType<typeof vi.spyOn>;
let rate: ReturnType<typeof vi.spyOn>;
beforeEach(() => {
  vi.spyOn(console, "error").mockImplementation(() => undefined);
  ai = vi.spyOn(env.AI, "run").mockResolvedValue(nova(" Hello from ClearFlow. "));
  rate = vi.spyOn(env.TRANSCRIBE_LIMITER, "limit").mockResolvedValue({ success: true });
});
afterEach(() => vi.restoreAllMocks());

describe("routing and authentication", () => {
  it("returns only service/model health without requiring a token", async () => {
    const { response, body } = await result(new Request("https://clearflow.test/health"));
    expect(response.status).toBe(200);
    expect(body).toEqual({ service: "clearflow-dictation", model: "@cf/deepgram/nova-3" });
    expect(ai).not.toHaveBeenCalled();
  });
  it("rejects unknown routes and wrong methods", async () => {
    expect((await result(new Request("https://clearflow.test/unknown"))).response.status).toBe(404);
    expect((await result(new Request("https://clearflow.test/v1/transcribe"))).response.status).toBe(405);
  });
  it.each(["", "Bearer wrong", "Bearer test-only-token-extra", "Basic test-only-token"])("rejects auth %s before reading body or rate limit", async token => {
    const req = request(payload(), { Authorization: token });
    const { response, body } = await result(req);
    expect(response.status).toBe(401); expect(body.error.code).toBe("UNAUTHORIZED");
    expect(req.bodyUsed).toBe(false); expect(ai).not.toHaveBeenCalled(); expect(rate).not.toHaveBeenCalled();
  });
  it("fails closed when the secret is absent", async () => {
    const { response, body } = await result(request(), { ...env, AUTH_TOKEN: "" });
    expect(response.status).toBe(503); expect(body.error.code).toBe("NOT_CONFIGURED");
    expect(ai).not.toHaveBeenCalled();
  });
  it("rejects rate-limited requests without calling AI", async () => {
    rate.mockResolvedValue({ success: false });
    const { response, body } = await result();
    expect(response.status).toBe(429); expect(body.error.code).toBe("RATE_LIMITED");
    expect(response.headers.get("Retry-After")).toBe("60"); expect(ai).not.toHaveBeenCalled();
  });
});

describe("bounded input", () => {
  it("rejects non-JSON content types", async () => {
    const { response } = await result(request(payload(), { "Content-Type": "text/plain" }));
    expect(response.status).toBe(415); expect(ai).not.toHaveBeenCalled();
  });
  it.each([undefined, "1"])("bounds streamed body with content-length %s", async contentLength => {
    let cancelled = false;
    let count = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) { controller.enqueue(new Uint8Array(1024 * 1024)); count++; },
      cancel() { cancelled = true; },
    });
    const headers: Record<string, string> = { Authorization: "Bearer test-only-token", "Content-Type": "application/json" };
    if (contentLength) headers["Content-Length"] = contentLength;
    const req = new Request("https://clearflow.test/v1/transcribe", { method: "POST", headers, body: stream });
    const { response, body } = await result(req);
    expect(response.status).toBe(413); expect(body.error.code).toBe("BODY_TOO_LARGE");
    expect(cancelled).toBe(true); expect(count).toBeLessThanOrEqual(16); expect(ai).not.toHaveBeenCalled();
  });
  it("rejects oversized declared body without reading it", async () => {
    const req = request(payload(), { "Content-Length": String(maxBody + 1) });
    expect((await result(req)).response.status).toBe(413); expect(req.bodyUsed).toBe(false);
  });
  it("rejects invalid JSON", async () => {
    const req = new Request("https://clearflow.test/v1/transcribe", { method: "POST", headers: { Authorization: "Bearer test-only-token", "Content-Type": "application/json" }, body: "{" });
    expect((await result(req)).body.error.code).toBe("INVALID_JSON");
  });
  it.each([null, [], {}, { audio: "AAAA", requestId: "invalid" }])("rejects invalid request shapes", async value => {
    expect((await result(request(value))).response.status).toBe(400); expect(ai).not.toHaveBeenCalled();
  });
  it.each(["!bad", "AAAA\n", "A===", "AB==", "", 123])("rejects malformed base64 %s", async audio => {
    const { body, response } = await result(request(payload({ audio })));
    expect(response.status).toBe(400); expect(body.requestId).toBe(requestId); expect(ai).not.toHaveBeenCalled();
  });
  it("enforces decoded audio limit below the JSON limit", async () => {
    const { response, body } = await result(request(payload({ audio: base64(new Uint8Array(10 * 1024 * 1024 + 1)) })));
    expect(response.status).toBe(413); expect(body.error.code).toBe("AUDIO_TOO_LARGE"); expect(ai).not.toHaveBeenCalled();
  });
  it.each([base64(new Uint8Array(100)), base64(wav().subarray(0, 100)), base64(wav(0.1))])("rejects corrupt or too-short WAV", async audio => {
    expect((await result(request(payload({ audio })))).response.status).toBe(400); expect(ai).not.toHaveBeenCalled();
  });
  it("rejects inconsistent sample format metadata", async () => {
    const audio = wav(); new DataView(audio.buffer).setUint32(28, 1, true);
    expect((await result(request(payload({ audio: base64(audio) })))).response.status).toBe(400);
    expect(ai).not.toHaveBeenCalled();
  });
  it("accepts WAV files with an extra padded metadata chunk", async () => {
    const source = wav();
    const audio = new Uint8Array(source.length + 10);
    audio.set(source.subarray(0, 12));
    audio.set(new TextEncoder().encode("JUNK"), 12);
    new DataView(audio.buffer).setUint32(16, 1, true);
    audio.set(source.subarray(12), 22);
    new DataView(audio.buffer).setUint32(4, audio.length - 8, true);
    expect((await result(request(payload({ audio: base64(audio) })))).response.status).toBe(200);
  });
  it("rejects recordings beyond five minutes before inference", async () => {
    const { response, body } = await result(request(payload({ audio: base64(wav(301)) })));
    expect(response.status).toBe(413); expect(body.error.code).toBe("AUDIO_TOO_LONG");
    expect(ai).not.toHaveBeenCalled();
  });
  it("rejects a WAV chunk whose declared length crosses the file boundary", async () => {
    const audio = wav(); new DataView(audio.buffer).setUint32(40, audio.length, true);
    expect((await result(request(payload({ audio: base64(audio) })))).response.status).toBe(400);
    expect(ai).not.toHaveBeenCalled();
  });
  it.each([{ vocabulary: "x".repeat(1001) }, { vocabulary: 2 }, { language: "english!!!" }, { language: 2 }])("rejects invalid hints", async hints => {
    expect((await result(request(payload(hints)))).response.status).toBe(400); expect(ai).not.toHaveBeenCalled();
  });
});

describe("inference boundary", () => {
  it("passes documented model options and correlates success", async () => {
    const input = payload({ language: "en", vocabulary: "ClearFlow, Exampletown" });
    const { response, body } = await result(request(input));
    expect(response.status).toBe(200);
    expect(ai).toHaveBeenCalledWith("@cf/deepgram/nova-3", {
      audio: { body: expect.any(ReadableStream), contentType: "audio/wav" },
      language: "en", keyterm: "ClearFlow, Exampletown", punctuate: true, smart_format: true,
    });
    const sentAudio = new Uint8Array(await new Response(ai.mock.calls[0][1].audio.body).arrayBuffer());
    expect(sentAudio).toEqual(wav());
    expect(body).toMatchObject({ text: "Hello from ClearFlow.", requestId, model: "@cf/deepgram/nova-3" });
    expect(body.durationMs).toBeGreaterThanOrEqual(0); expect(response.headers.get("Cache-Control")).toBe("no-store");
  });
  it("omits language and vocabulary for automatic detection", async () => {
    await result(request(payload({ language: "auto" })));
    expect(ai.mock.calls[0][1]).not.toHaveProperty("language");
    expect(ai.mock.calls[0][1]).not.toHaveProperty("keyterm");
    expect(ai.mock.calls[0][1]).toHaveProperty("detect_language", true);
  });
  it("returns no-speech without substituting invented text", async () => {
    ai.mockResolvedValue(nova("  "));
    const { response, body } = await result();
    expect(response.status).toBe(422); expect(body.error.code).toBe("NO_SPEECH"); expect(body.requestId).toBe(requestId);
  });
  it.each([null, {}, { text: "legacy response" }, { results: {} }, { results: { channels: [] } }, { results: { channels: [{ alternatives: [{ transcript: 123 }] }] } }])("rejects malformed upstream response", async upstream => {
    ai.mockResolvedValue(upstream);
    const { response, body } = await result();
    expect(response.status).toBe(502); expect(body.error.code).toBe("INVALID_MODEL_RESPONSE"); expect(body.requestId).toBe(requestId);
  });
  it("hides upstream error details and preserves request correlation", async () => {
    ai.mockRejectedValue(new Error("private upstream transcript/token"));
    const log = vi.spyOn(console, "error");
    const { response, body } = await result();
    expect(response.status).toBe(502); expect(body.error.code).toBe("TRANSCRIPTION_FAILED"); expect(body.requestId).toBe(requestId);
    expect(JSON.stringify(body)).not.toContain("private"); expect(JSON.stringify(log.mock.calls)).not.toContain("private");
  });
});
