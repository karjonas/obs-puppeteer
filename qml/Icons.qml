// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Apart from `app`, these are OBS Studio's own icons, redistributed under its
// "GPL v2 or any later version" clause; see resources/icons/obs/ATTRIBUTION.md.
//
// The OBS icons are monochrome: use them through a control's `icon` property
// so they can be recoloured per state.

pragma Singleton
import QtQuick

QtObject {
    readonly property url audio: "qrc:/qt/qml/OBSPuppeteer/icons/audio.svg"
    readonly property url mute: "qrc:/qt/qml/OBSPuppeteer/icons/mute.svg"

    readonly property url close: "qrc:/qt/qml/OBSPuppeteer/icons/close.svg"

    // This app's own icon, full colour, for use in an Image.
    readonly property url app: "qrc:/qt/qml/OBSPuppeteer/icons/obs-puppeteer.svg"

    readonly property url visible: "qrc:/qt/qml/OBSPuppeteer/icons/visible.svg"
    readonly property url invisible: "qrc:/qt/qml/OBSPuppeteer/icons/invisible.svg"
}
