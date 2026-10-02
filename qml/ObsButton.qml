// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import OBSPuppeteer

// A button drawn like OBS's QPushButton: flat, lighter on hover, darker when
// pressed, filled with the primary colour when checked.
Button {
    id: control

    // Fill when checked. Separate shades rather than Qt.lighter(), because Yami's
    // colours are hand-picked.
    property color accent: Theme.primary
    property color accentLight: Theme.primaryLight
    property color accentLighter: Theme.primaryLighter

    implicitHeight: 34
    leftPadding: Theme.paddingLarge
    rightPadding: Theme.paddingLarge
    // The style's 14px vertical padding leaves no room for content at this height.
    topPadding: 0
    bottomPadding: 0

    // Material insets the background to make room for a shadow.
    topInset: 0
    bottomInset: 0
    leftInset: 0
    rightInset: 0

    // Don't let a layout squash it.
    Layout.minimumHeight: implicitHeight

    // A row so the button can have an icon; without one the label fills it and
    // still elides.
    contentItem: RowLayout {
        spacing: Theme.spacing

        Image {
            visible: String(control.icon.source) !== ""
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: control.icon.width
            Layout.preferredHeight: control.icon.height
            source: control.icon.source
            sourceSize.width: control.icon.width
            sourceSize.height: control.icon.height
            // The icons are white; dim them like a disabled label.
            opacity: control.enabled ? 1.0 : 0.5
        }

        Label {
            // fillHeight too, or the label sits off-centre.
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: control.text
            font: control.font
            color: control.enabled ? Theme.text : Theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    background: Rectangle {
        radius: Theme.radius
        border.width: 1

        color: {
            if (!control.enabled)
                return Theme.bgInputDisabled
            if (control.down)
                return control.checked ? control.accent : Theme.bgInputDown
            if (control.checked)
                return control.hovered ? control.accentLight : control.accent
            return control.hovered ? Theme.bgInputHover : Theme.bgInput
        }

        border.color: {
            if (control.checked)
                return (control.hovered || control.visualFocus) ? control.accentLighter : control.accentLight
            if (control.down)
                return Theme.border
            return (control.hovered || control.visualFocus) ? Theme.borderHover : Theme.border
        }
    }
}
