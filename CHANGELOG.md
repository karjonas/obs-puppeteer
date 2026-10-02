# Changelog

Notable changes to OBS Puppeteer. Dates are release dates; this project follows
[semantic versioning](https://semver.org/), and anything below 1.0 may still
change shape between releases.

## 0.1.0 — 2026-10-02

Initial release.

- Runs on Linux (AppImage) and Windows (single-file exe).
- Scenes, with live preview thumbnails, switched with one click.
- The current scene's sources, with visibility toggles.
- Audio inputs: mute, volume with a dB readout, and live level meters.
- Streaming and recording: start, stop, and how long each has been running.
- Studio Mode: preview and program side by side, a transition picker and a
  transition button.
- OBS info: FPS, CPU, bitrate and skipped frames.
- Remembers addresses that have connected before, and marks which are reachable.

### Known limitations

- The Windows executable is unsigned, so SmartScreen warns on first run.
- No macOS package yet. Building from source works; CI builds and tests it on
  macOS.
