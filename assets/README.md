# ClearFlow app icon

The original seven-bar ClearFlow waveform uses a white mark on a dark plum rounded tile, with transparent macOS icon margins. It follows the app's existing waveform identity. No third-party artwork is included.

- `AppIcon.icns`: Finder, Dock and application-switcher icon, bundled by `scripts/build-app.sh`.
- `AppIcon.png`: 1024-pixel transparent preview/export.
- `../scripts/render-app-icon.swift`: editable native drawing source, under the repository MIT license.

Rebuild all icon resolutions on macOS with Command Line Tools installed:

```sh
scripts/generate-icon.sh
scripts/build-app.sh
```

The ICNS contains 16, 32, 64, 128, 256, 512 and 1024-pixel images. Builds use the committed icon, so routine app compilation does not require regeneration.
