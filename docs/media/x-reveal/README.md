# ClearFlow reveal kit

Post-ready launch assets with anonymous sample content. No recordings, personal dictations, service addresses, account IDs or machine paths are shown. The public repository URL is the call to action.

## Files

- `clearflow-reveal.png`: landscape reveal graphic. Created with the built-in image generator, using the app screenshot as a style reference. It is promotional artwork, not a UI screenshot.
- `clearflow-demo-landscape.mp4`: 23-second, 1280 × 720, 24 fps, H.264 video.
- `clearflow-demo-portrait.mp4`: 23-second, 720 × 900 (4:5), 24 fps, H.264 video.

Both videos contain a silent AAC track and readable on-screen captions. Use the portrait version for a taller feed post, or landscape for a wider desktop presentation. The illustrated sequence uses the app’s actual recording-bar/main-view components with synthetic text and waveform measurements. The overlay is enlarged for readability. It does not perform live capture, inference or paste and does not represent measured latency. Those disclosures appear in the video.

Encoding follows the H.264/MP4 and AAC formats described in [X’s media specifications](https://help.x.com/en/using-twitter/media-studio-faqs.html). Exported files are well below the usual upload size/duration limits.

## Suggested reveal post

I built ClearFlow: open-source dictation for Mac.

⌥⇧Space → speak → text in your selected field.

Runs Whisper large-v3-turbo on your own hardware. No cloud account required.

App + source: https://github.com/ichen27/clearflow

## Reproduce the videos

On macOS with Swift 6 and FFmpeg on PATH:

```sh
scripts/build-reveal.sh
```

Frames are generated under ignored `work/reveal/`. MP4s and a copy of the reveal image are written under ignored `dist/x-reveal/`. The source renderer does not access Keychain, saved history, microphone, transcription endpoints or the clipboard. The new command is a documentation renderer and does not change normal dictation behavior.

The video sources are in `Sources/ClearFlow/SocialPreview.swift`; the UI components are reused from the app. No third-party music or stock footage is included.

## Image generation

Mode: built-in image generator. Reference: the repository's synthetic `docs/media/screenshot.png`.

Prompt:

> Create a polished launch/reveal graphic for X for the actual open-source macOS dictation app ClearFlow. Landscape 16:9 composition. Use the attached real app screenshot only as a visual reference for its warm ivory, charcoal green, restrained amber palette and original waveform motif. Do not invent app screens or tiny UI text. Make an editorial typographic product announcement: warm ivory background, very large confident near-black sans-serif title 'Meet ClearFlow.' and large second line 'Your voice. Your Mac.' in a beautiful restrained serif. Small uppercase eyebrow 'OPEN-SOURCE DICTATION'. Feature a crisp isolated compact black recording capsule with gray circular X at left, ten tiny white waveform bars in the center and white circular checkmark at right, matching the actual application's simple overlay style. The capsule can be enlarged for the poster, with lots of negative space and a soft natural shadow. Gentle sweeping waveform line or vertical waveform sticks as a subtle supporting graphic, in warm muted orange. Bottom supporting copy exactly 'Local Whisper. No cloud account required.' Small footer exactly 'macOS · Apple Silicon' and 'github.com/ichen27/clearflow'. Premium independent software launch aesthetic, flat editorial art direction, precise legible typography, meticulous spacing, strong visual hierarchy, clean uncluttered layout. Only the specified words. No personal endpoint, account IDs, private information, Wispr branding, laptops, people, fake feature panels, badges, locks, claims of speed, or security guarantees. Use the repository URL as the public call to action.
