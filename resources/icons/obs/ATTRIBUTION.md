# OBS Studio icons

The SVG files in this directory are taken unmodified from OBS Studio, so that
this window's controls carry the same glyphs as the ones they mirror in OBS.

    Copyright (C) OBS Studio contributors
    Upstream: https://github.com/obsproject/obs-studio

OBS Studio is distributed under the GNU General Public License v2 "or any later
version". That is stated at the project level, in its `README.rst`, which is the
citation that matters here: these are data files, and like the theme they carry
no licence header of their own (`COPYING` holds the GPL v2 text, and the "or
later" wording appears in per-file headers such as `frontend/OBSApp.cpp` — but
not on every file, and not on these). They are redistributed here as
GPL-3.0-or-later under that clause, matching this project's licence.

## Files

Copied from OBS Studio 32.2.2 as installed on Arch Linux, and from a source
checkout at commit `6b3e55072`:

| File            | Upstream path                                  |
| --------------- | ---------------------------------------------- |
| `audio.svg`     | `frontend/data/themes/Dark/settings/audio.svg`  |
| `mute.svg`      | `frontend/data/themes/Dark/mute.svg`            |
| `visible.svg`   | `frontend/data/themes/Dark/visible.svg`         |
| `close.svg`     | `frontend/data/themes/Dark/close.svg`           |
| `invisible.svg` | `frontend/forms/images/invisible.svg`           |

Each file is copied byte for byte; none has been edited, recoloured or
re-exported. The pairings are OBS's own, not a guess: the Yami theme sets `.btn-mute` to
`audio.svg` and `.btn-mute.checked` to `mute.svg`, and `.indicator-visibility`
to `visible.svg` when checked and `invisible.svg` when unchecked.

## Authorship

Per `git log --follow` on the files upstream, OBS's icons were introduced in SVG
form by Clayton Groeneveld ("UI: Change icons to svg", 2019-04-20) and redrawn
into their present form by Georges Basile Stavracas Neto ("UI: Rework icons",
2022-07-30).
