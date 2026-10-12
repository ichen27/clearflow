# Contributor instructions

ClearFlow is an independent macOS dictation app with self-hosted transcription.
No proprietary application code or assets belong here.

## Architecture

- `Sources/ClearFlow`: SwiftUI/AppKit capture, shortcut, settings, authenticated API client and guarded paste.
- `Sources/ClearFlowCore`: pure lifecycle, meter and endpoint validation.
- `local-stt`: loopback HTTP API backed by MLX Whisper on Apple Silicon.
- `worker`: optional Cloudflare Workers AI Nova 3 API, deployed to each operator's own account.
- `docs/media`: reproducible UI renders using synthetic content only.

## Workflow

Read README.md and the relevant backend README before editing. Inspect branch, remote and uncommitted work. Use focused feature/fix branches, coherent commits and PRs; do not push implementation directly to main or force-push shared history. Push completed work and verify the remote SHA. Review the diff and wait for current-revision CI before an authorized merge. Sync the local default branch afterward.

Never commit credentials, actual service endpoints, account IDs, local machine paths, personal transcripts, recordings, runtime logs, caches, dependencies or weights. Examples use localhost or reserved example domains. Release builds must contain only the loopback default. Use anonymous synthetic fixtures in documentation and demos. Keep private operational notes outside this repository.

## Validation

```sh
scripts/test-native.sh
scripts/test-shortcut-registration.sh
scripts/build-app.sh
python3 -m unittest discover -s local-stt -v
python3 scripts/check-distribution.py
cd worker && npm ci && npm test && npm run typecheck && npm run build
```

CI checks native compilation/core behavior, local HTTP/setup contracts, Worker tests/types/dry-run and distribution privacy rules. Real microphone capture, cross-app insertion and model inference require device validation; never claim those from mocked tests. Never bypass macOS permissions. Public releases are ad-hoc signed until a maintainer supplies Developer ID signing and notarization.
