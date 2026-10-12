# ClearFlow transcription Worker

Private, single-user speech recognition using Deepgram Nova 3 on Cloudflare Workers AI. No storage bindings and no application persistence of audio or transcripts.

## Run and verify

Use Node.js 22.17 or later . From this directory:

```sh
npm ci
npm run types
npm run typecheck
npm test
npm run build
```

Tests run in workerd through Cloudflare's Vitest plugin. Remote bindings are disabled in the test configuration, and the AI boundary is mocked. `npm run build` only packages a deployment with `--dry-run`; it does not deploy.

For manual development, put a private `AUTH_TOKEN` in ignored `.dev.vars` and run `npm run dev`. The AI binding accesses the real Cloudflare model and may incur usage charges during manual development. Do not use the test suite's dummy credential in deployment.

## Deployment

Run `npx wrangler login` to select your own Cloudflare account. Change the Worker name in `wrangler.jsonc` if needed. No account ID or hosted endpoint is bundled. Install the `AUTH_TOKEN` secret through Wrangler's secure prompt or protected stdin. `npm run deploy` deploys the Worker. A missing/empty secret makes transcription fail closed with 503. The unprotected health route does not prove the secret or model is working.

## API

`GET /health` returns only `{service, model}`.

`POST /v1/transcribe` requires `Authorization: Bearer TOKEN` and `Content-Type: application/json`. JSON fields:

- `requestId`: UUID, returned unchanged for correlation. This does not deduplicate repeated requests.
- `audio`: standard canonical base64 containing a complete RIFF/WAV file; 16-bit little-endian PCM, one or two channels, 8–48 kHz, 0.25–300 seconds. 16 kHz mono is recommended for the app.
- `language`: optional two/three-letter language code; blank or `auto` selects automatic detection.
- `vocabulary`: optional string, at most 1000 JavaScript string code units, passed as Nova 3's keyterm hint. It is a hint, not a guaranteed spelling rule.

Limits: 10 MiB decoded audio, 14 MiB UTF-8 JSON. Actual streamed bytes are bounded before JSON parsing regardless of Content-Length. WAV metadata chunks and padding are supported; malformed or truncated chunks are rejected.

Success: `{text, requestId, model, durationMs}`. `durationMs` is elapsed server request-processing time, not audio duration. Responses use `Cache-Control: no-store`.

Errors: `{error:{code,message}, requestId?}`. Correlation is included after a valid request ID has been parsed. Authentication, early size rejection, and rate-limit responses may not include one.

| Status | Meaning |
| --- | --- |
| 400 | Invalid JSON, UUID, base64, WAV, language/vocabulary, or too-short recording |
| 401 | Missing/incorrect bearer token |
| 413 | Body/audio/duration limit exceeded |
| 415 | Unsupported Content-Type |
| 422 | Model returned no detected speech (`NO_SPEECH`) |
| 429 | Rate limited; Retry-After is 60 seconds |
| 502 | Model call failed or returned an invalid response |
| 503 | Missing secret or temporarily unavailable service |

The authenticated personal service is limited to 30 requests/minute per Cloudflare location. Cloudflare's limiter is approximate, not a strict global spending cap. Authentication runs before the limiter and body reader. No CORS configuration is needed for the native app.

## Privacy and operations

Secrets are compared through fixed-size SHA-256 digests and timing-safe comparison. Application logs contain only a fixed event/code and a validated request UUID on server errors. Audio, vocabulary, authorization headers, model exception details, and transcripts are not logged. Worker observability is disabled by default. There is no AI Gateway logging/cache configured. Cloudflare still processes the submitted audio under its service policies.

The app owns recording, cancellation, retry, and paste behavior. Cancelling the client does not promise cancellation of already-started model work.

## References

- [Nova 3 model input/output](https://developers.cloudflare.com/workers-ai/models/nova-3/)
- [Workers runtime testing](https://developers.cloudflare.com/workers/testing/vitest-integration/write-your-first-test/)
- [Rate-limiter behavior](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)
- [Wrangler configuration](https://developers.cloudflare.com/workers/wrangler/configuration/)
