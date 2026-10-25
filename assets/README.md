# ClearFlow app icon

The approved five-bar waveform uses an ivory mark on a softly shaded dark tile, with transparent macOS icon margins. No third-party artwork is included.

- `AppIcon.png`: approved 1280-pixel bitmap master; edit this file to change the artwork.
- `AppIcon.icns`: Finder, Dock and application-switcher icon, bundled by `scripts/build-app.sh`.
- `../scripts/generate-icon.sh`: packages the master into all standard icon resolutions using macOS image tools.
- `../scripts/render-app-icon.swift`: retained editable drawing source for the earlier seven-bar concept; it does not generate the current icon.

Rebuild the ICNS on macOS:

```sh
scripts/generate-icon.sh
scripts/build-app.sh
```

The ICNS contains 16, 32, 64, 128, 256, 512 and 1024-pixel images. Builds use the committed ICNS; normal app compilation does not regenerate the artwork. Icon assets and the retained drawing source are covered by the repository MIT license.
