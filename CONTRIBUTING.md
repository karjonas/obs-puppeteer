# Contributing

Report bugs and request features by opening an
[issue](https://github.com/karjonas/obs-puppeteer/issues). Pull requests that
fix bugs are welcome; for a new feature, open an issue first so we can agree on
it before you spend time on it.

Contributions are accepted under GPL-3.0-or-later, the project's licence. You
keep the copyright to what you contribute.

## Building

Requires Qt 6.8+ (Core, Gui, Qml, Quick, QuickControls2, WebSockets, Svg) and
CMake 3.21+.

Ubuntu 22.04 and 24.04 ship older Qt (6.2 and 6.4), so the build can't use
their packages. Use the AppImage there, or install Qt 6.8+ with the
[Qt online installer](https://www.qt.io/download-qt-installer) or
[aqtinstall](https://github.com/miurahr/aqtinstall), which is what CI does.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/obs-puppeteer
```

## Testing

`tests/` contains a Qt Test suite (43 cases) that spins up a mock
obs-websocket server (`MockObsServer`) and exercises `ObsClient`'s protocol
handling directly, with no real OBS instance required:

- Auth handshake: no password, correct password, wrong password
- Scenes: list parsing, switching, `CurrentProgramSceneChanged`/`SceneListChanged` events
- Scene preview thumbnails: `GetSourceScreenshot` parsing (prefixed and bare
  base64), preserved across a scene-list refresh
- Sources: scene item list parsing, visibility toggling, `SceneItemEnableStateChanged`
- Audio: non-audio input kinds filtered out, initial mute/volume population,
  `InputMuteStateChanged`/`InputVolumeChanged` events, `InputCreated` refresh,
  mute/volume control requests
- Stream/record: status polling and all six start/stop/toggle controls
- Disconnect state reset, auto-reconnect after an unexpected drop, and
  resilience to malformed/unknown protocol messages
- Studio Mode: state on connect, entering/exiting studio mode fetches/clears
  the preview scene, `CurrentPreviewSceneChanged`/`CurrentSceneTransitionChanged`
  events, transition list parsing, and the preview/transition/program controls
- Audio meters: that `InputVolumeMeters` is subscribed to explicitly (it is not
  part of `EventSubscription::All`, and nothing fails visibly if that is
  dropped - the meters simply never move), level conversion, and that a level
  rises at once but falls gradually
- Stats: `GetStats` parsing, and a stream bitrate derived from the byte counter
- Which address was connected to, and whether a probed port is listening

`tests/qml/` contains Qt Quick Tests (79 cases) covering QML-level behaviour the
C++ suite above can't see, driven by `MockObsServerQml` - a QML-facing wrapper
around the same `MockObsServer` - so none of them need a real OBS:

- `tst_ScenesPanel.qml`: the click handler routes to `setCurrentPreviewScene`
  or `setCurrentProgramScene` depending on `obs.studioModeEnabled`, with a
  simulated mouse click
- `tst_ScrollExtents.qml`, `tst_PanelSizing.qml`: served far more scenes,
  sources and audio inputs than a real setup is likely to have, since the
  failures these guard - content clipped away with no way to scroll to it, a
  panel squashed until its meters are cut off - are invisible on a machine with
  two audio inputs
- `tst_ConnectionView.qml`: which address is remembered, that the history is
  most-recent-first without duplicates and stops at its cap, that picking an
  entry restores its port, that the × and Shift+Delete forget one address, and
  that connecting with **Remember this address** unticked saves nothing new
- `tst_PanelInteractions.qml`: that a visibility toggle asks for the opposite
  of what it is showing, and that the mute button names the right input
- `tst_StatusBar.qml`, `tst_Disconnect.qml`: how the rate and skipped-frame
  numbers are phrased and when they appear, and that closing a connection
  asks first, does nothing if cancelled, and stays closed rather than being
  undone by the reconnect timer
- `tst_LevelMeter.qml`, `tst_AudioPanel.qml`, `tst_Icons.qml`: meter zone
  geometry, the dB readout's formatting, and that each SVG icon actually decodes
- `tst_AboutDialog.qml`: that the About dialog opens, names the Qt it runs
  on, carries both licence texts, and scrolls rather than spilling out of the
  shortest window the app allows

The `OBSPuppeteer` QML module is built as its own static library
(`obs-puppeteer-qml`) precisely so it can be shared between the app and these
test targets.

```sh
cmake --build build
ctest --test-dir build --output-on-failure
```

## Formatting and linting

C++ follows Qt's own style, in [`.clang-format`](.clang-format) (copied from
Qt's). The tree is formatted with clang-format 22.1.8; other releases shift the
output slightly, so format with that version:

```sh
pipx run clang-format==22.1.8 -i $(git ls-files '*.cpp' '*.h')
```

QML is linted, not formatted: qmlformat breaks long bindings mid-call, and its
output differs between Qt versions. The lint target lists any warnings but
succeeds regardless, so read its output:

```sh
cmake --build build --target all_qmllint
```

Licensing follows [REUSE](https://reuse.software): every file carries an SPDX
header or is covered by [`REUSE.toml`](REUSE.toml).

```sh
pipx run reuse lint
```

## Continuous integration and packages

`.github/workflows/build.yml` builds and tests on Linux, Windows and macOS for
every push and pull request, and packages every run too: a Linux AppImage and a
fully static, single-file Windows `.exe`, downloadable from the run's page for
seven days so any commit can be tried out. When the push is a `v*` tag, both
are also attached to a GitHub Release.

The static Qt build below costs an hour or two whenever its cache has expired,
which happens after seven days without a hit; any run in between keeps it warm.

- **Linux**: `linuxdeploy` + `linuxdeploy-plugin-qt` bundle Qt (libs, plugins,
  QML modules) around the built executable into a single `.AppImage`. The
  Wayland platform plugin is requested explicitly — the default bundle carries
  only `xcb`, which leaves the AppImage running through XWayland on the
  desktops that now default to Wayland. CI then runs the AppImage headlessly
  before uploading it, since a missing plugin or QML module does not fail a
  build, only a first launch. This pipeline was verified locally: built, run
  standalone, and connected to a live OBS instance.
- **Windows**: a fast `test-windows` job builds and tests `obs-puppeteer`
  against a prebuilt shared Qt first (same as Linux), so an MSVC-specific
  break is caught in minutes. Only after that passes does `package-windows`
  build Qt itself from source (qtbase, qtshadertools, qtdeclarative,
  qtwebsockets) with `-static -static-runtime` — no precompiled static Qt kit
  exists — and link `obs-puppeteer` against it with MSVC. The result is one
  `.exe` with no Qt DLLs and no VC++ Redistributable dependency — genuinely
  download-and-run. The static Qt build is cached across CI runs since it's
  slow (1-2+ hours on a cache miss, seconds otherwise). CI checks the result's
  import table names no Qt DLL and no MSVC runtime, which is the portability
  claim made testable.
- **macOS**: built and tested only (`test-macos`), with no package yet. An
  unsigned app is hard to open on recent macOS, so a `.dmg` is worth adding
  once it can be signed and notarized, which needs an Apple Developer account.

To build a package locally on Linux:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
DESTDIR=build/AppDir cmake --install build --prefix /usr
# grab linuxdeploy + linuxdeploy-plugin-qt from https://github.com/linuxdeploy
QML_SOURCES_PATHS=$(pwd)/qml QMAKE=qmake6 NO_STRIP=1 \
  EXTRA_PLATFORM_PLUGINS="libqwayland.so;libqoffscreen.so" \
  ./linuxdeploy-x86_64.AppImage --appimage-extract-and-run \
  --appdir build/AppDir --executable build/obs-puppeteer \
  --desktop-file resources/obs-puppeteer.desktop \
  --icon-file resources/icons/obs-puppeteer.png \
  --plugin qt --output appimage
```

## Releasing

1. Set the version in `project(VERSION ...)` in `CMakeLists.txt`, and add a
   section for that version to [CHANGELOG.md](CHANGELOG.md).
2. Tag that commit `v<version>`, e.g. `v0.2.0`; a suffix such as `v0.2.0-rc1`
   is published as a pre-release.
3. Push the tag. CI builds the packages and publishes the release.

A build of a tagged commit fails if the tag does not match `project()`, so a
mismatch shows up in the first build after tagging, before anything is
published.
