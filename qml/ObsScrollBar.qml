// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import OBSPuppeteer

// A scroll bar drawn like OBS's that stays visible whenever there's more to
// scroll to, instead of fading out. Sizes and colours from Yami's QScrollBar
// rules.
ScrollBar {
    id: control

    policy: (size > 0 && size < 1) ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

    implicitWidth: 12
    implicitHeight: 12
    padding: 2

    contentItem: Rectangle {
        implicitWidth: 8
        implicitHeight: 8
        radius: Theme.radiusSmall
        color: Theme.bgInput
    }

    background: Rectangle {
        color: Theme.bgBase
        radius: Theme.radius
    }
}
