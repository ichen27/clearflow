# Documentation media

`screenshot.png` is rendered from the actual SwiftUI main view with synthetic sample history. `demo.gif` is a labeled UI walkthrough using the actual recording bar, a sample editor, and synthetic waveform/text. It does not perform microphone capture, model inference or automatic insertion and makes no timing claim.

Reproduce on macOS after building, with Pillow installed in a separate tooling environment:

```sh
dist/ClearFlow.app/Contents/MacOS/ClearFlow --render-media work/media
python3 scripts/assemble-demo.py work/media docs/media
```

The renderer bypasses normal app startup and does not read Keychain or saved transcript history. Never replace these with screenshots containing personal dictations, tokens, endpoints or account details.

## Recording recovery warning

[recovery-warning.png](recovery-warning.png) renders the actual nonactivating warning component with synthetic copy. It illustrates the message retained after unexpected recording termination; it is not evidence of a physical device interruption. The existing --render-media command produces this image alongside the walkthrough frames.
