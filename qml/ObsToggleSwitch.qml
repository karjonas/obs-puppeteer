// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import OBSPuppeteer

// OBS's toggle switch (idian::ToggleSwitch), with the label on the left.
// Sizes are Yami's --toggle_* values.
Switch {
    id: control

    padding: 0
    spacing: Theme.spacingLarge
    implicitHeight: Math.max(trackHeight, contentItem.implicitHeight)

    readonly property int trackWidth: 40
    readonly property int trackHeight: 20
    readonly property int handleSize: 13
    readonly property int handleMargin: 3

    Layout.minimumHeight: implicitHeight

    indicator: Rectangle {
        x: control.width - width
        y: (control.height - height) / 2
        implicitWidth: control.trackWidth
        implicitHeight: control.trackHeight
        radius: height / 2

        // Off: --grey7 rather than Yami's --grey6, which is the panel colour here.
        color: control.checked
               ? (control.hovered ? Theme.primaryLight : Theme.primary)
               : (control.hovered ? Theme.bgInput : Theme.bgWindow)

        border.width: 1
        border.color: {
            if (control.visualFocus)
                return Theme.primaryLighter
            if (!control.hovered)
                return "transparent"
            return control.checked ? Theme.text : Theme.bgInput
        }

        Rectangle {
            width: control.handleSize
            height: control.handleSize
            radius: height / 2
            color: Theme.text
            y: (parent.height - height) / 2
            x: control.checked ? parent.width - width - control.handleMargin : control.handleMargin

            Behavior on x {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
        }
    }

    contentItem: Label {
        text: control.text
        font: control.font
        color: control.enabled ? Theme.text : Theme.textMuted
        verticalAlignment: Text.AlignVCenter
        rightPadding: control.indicator.width + control.spacing
    }
}
