# Local Whisper

Run `mlx-community/whisper-large-v3-turbo` on your own Apple Silicon Mac. Pinned model revision: `a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb`. The app and service can run on the same Mac; no cloud account is required.

## Setup

Install Python 3.12, then run from the repository root:

```sh
python3.12 local-stt/setup.py
python3.12 local-stt/run.py
```

In a second terminal, configure the installed app:

```sh
curl --fail http://127.0.0.1:8768/health
python3.12 local-stt/run.py --configure-app /Applications/ClearFlow.app
```

Run the app configuration command from a terminal in your logged-in macOS desktop session. Keychain can reject writes from SSH (error -25308); in that case configure the address/token in the app’s Settings instead.

Restart the app and grant normal Microphone/Accessibility permissions. The health check proves availability, not authenticated inference. To test the actual client with your own 16 kHz mono PCM16 WAV:

```sh
/Applications/ClearFlow.app/Contents/MacOS/ClearFlow --transcribe-file sample.wav
```

This prints the transcript to your terminal. Do not upload personal test recordings or output to Git.

## Storage and credentials

Default runtime: `~/Library/Application Support/ClearFlow/service`. It holds a virtual environment, pinned model, private `secrets.json`, `service-config.json`, and caches. Setup preserves existing tokens on rerun. Each new installation generates its own cryptographically random token; no shared credential is included.

Use `--runtime /path/to/your/runtime` on **every** setup/run/install-agent command to use another disk. Use `--port 18768` during setup if the default port is occupied; `run.py` and its app configuration helper read that saved port. Keep the runtime outside your checkout.

Setup downloads Python dependencies and the model once. Server launches set `HF_HUB_OFFLINE=1` and use the downloaded model directory. The service binds only to `127.0.0.1`; do not expose the Python HTTP server directly to the internet.

## Optional start at login

Stop the foreground server with Control-C first, then:

```sh
python3.12 local-stt/install-agent.py
```

The opt-in LaunchAgent is `org.clearflow.stt`. Keep the repository and runtime in their installed locations. Log files are in `~/Library/Logs/ClearFlow` and contain startup/status messages, not request bodies or transcripts. External drives must be mounted; grant ordinary macOS file-access permissions if prompted.

Stop the agent:

```sh
launchctl bootout gui/$(id -u)/org.clearflow.stt
```

To disable future login startup, move `~/Library/LaunchAgents/org.clearflow.stt.plist` out of LaunchAgents. To uninstall, stop the agent, then remove your runtime directory when you no longer need the model or token.

## Optional remote Mac

Install the service on the Apple Silicon Mac that will run inference. Keep its loopback binding. For example, use your own Tailscale network and HTTPS Serve on that host:

```sh
tailscale serve --bg --https=10443 http://127.0.0.1:8768
```

Use the HTTPS URL printed by **your** Tailscale installation, not an address copied from someone else. On the client Mac, enter that URL and your server's token in ClearFlow Settings → Transcription, then save. Transfer the token using a secure channel; do not paste it into an issue, screenshot or repository. The remote host must be awake and reachable. Do not enable public Funnel or reset unrelated Serve routes.

## Contract and privacy

`GET /health` reports the model and backend. Authenticated `POST /v1/transcribe` accepts JSON `{requestId, audio, language?, vocabulary?}`. `audio` is canonical base64 of a complete 16 kHz mono PCM16 WAV, 0.25–300 seconds, at most 10 MiB. Body limit: 14 MiB. Response: `{text, requestId, model, durationMs}`.

Only one upload/inference runs at a time; overlap returns 429. Audio stays in process memory. Requests/transcripts are not persisted or logged. Language detection and vocabulary hints are supported, but hints do not guarantee spelling. Whisper may hallucinate on noise or very quiet audio; exact digital silence is rejected.

## Troubleshooting and validation

- Connection refused: start the server and wait for its `ready` message; check the configured port.
- 401: configure the client with the token belonging to this runtime.
- 429: wait for the current recording to finish.
- Permission errors on another drive: approve macOS Files & Folders access normally.
- No insertion: check Accessibility, select an editable field before starting, and keep its content/cursor unchanged. Use clipboard fallback when needed.

```sh
python3 -m unittest discover -s local-stt -v
```

Contract tests substitute expensive inference. Test actual model transcription separately with synthetic or non-sensitive audio. Runtime setup tests verify unique credentials, private file modes, rerun preservation and configuration paths.
