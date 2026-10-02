// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Colours and metrics from OBS Studio's Yami theme
// (frontend/data/themes/Yami.obt, 32.2.x), principally by Warchamp7.
//
//   Copyright (C) OBS Studio contributors
//   GPL-2.0-or-later, used here as GPL-3.0-or-later.
//   Upstream: https://github.com/obsproject/obs-studio
//
// Only the values are reused; the controls are reimplemented in QML.

pragma Singleton
import QtQuick

// Names mirror the theme's: `--bg_base` is `bgBase`.
QtObject {
    // Palette
    readonly property color bgWindow: "#1D1F26"       // --grey7
    readonly property color bgBase: "#272A33"         // --grey6, panels
    readonly property color bgPreview: "#13141A"      // --grey8, behind a canvas
    readonly property color bgInput: "#3C404D"        // --grey4, --button_bg
    readonly property color bgInputHover: "#464B59"   // --grey3, --button_bg_hover
    readonly property color bgInputDown: "#1D1F26"    // --grey7, --button_bg_down
    readonly property color bgInputDisabled: "#272A33" // --grey6, --button_bg_disabled
    readonly property color border: "#3C404D"         // --border_color
    readonly property color borderHover: "#5B6273"    // --grey1, --button_border_hover

    readonly property color text: "#FFFFFF"           // --white1
    readonly property color textMuted: "#969696"      // --white5

    // Volume meter: dark shades for the unlit track, bright for the lit bar,
    // greys when muted.
    readonly property color meterNominal: "#37D247"        // --green2
    readonly property color meterWarning: "#E5AF24"        // --yellow2
    readonly property color meterError: "#E33B57"          // --red2
    readonly property color meterTrackNominal: "#17641E"   // --green5
    readonly property color meterTrackWarning: "#6E520D"   // --yellow5
    readonly property color meterTrackError: "#7D1224"     // --red5
    // The magnitude notch, a literal in Yami (`qproperty-magnitudeColor`).
    readonly property color meterMagnitude: "#000000"
    readonly property color meterMutedNominal: "#646464"   // --black4
    readonly property color meterMutedWarning: "#828282"   // --black5
    readonly property color meterMutedError: "#414141"     // --black3

    readonly property color primary: "#284CB8"        // --blue3
    readonly property color primaryLight: "#476BD7"   // --blue2
    readonly property color primaryLighter: "#718CDC" // --blue1
    readonly property color danger: "#C01C37"         // --red3, program/live
    readonly property color dangerLight: "#E33B57"    // --red2
    readonly property color dangerLighter: "#E85E75"  // --red1
    readonly property color success: "#25A231"        // --green3, preview
    readonly property color warning: "#B88A16"        // --yellow3, recording

    // Metrics
    readonly property int radius: 4                   // --border_radius
    readonly property int radiusSmall: 2
    readonly property int radiusLarge: 6

    readonly property int spacingSmall: 2
    readonly property int spacing: 4
    readonly property int spacingLarge: 8

    readonly property int padding: 8
    readonly property int paddingLarge: 12

    readonly property int fontSmall: 11
    readonly property int fontXSmall: 9
}
