// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import OBSPuppeteer

// A section of the window, drawn like an OBS dock.
Frame {
    id: root

    property string title: ""
    default property alias content: column.data

    // Height used by padding and the title, independent of the content, for
    // panels that fit their content to a height budget.
    readonly property real chromeHeight: topPadding + bottomPadding
                                         + (titleLabel.visible ? titleLabel.height + column.spacing : 0)

    padding: Theme.padding

    // Set explicitly because the content is anchor-filled.
    implicitWidth: column.implicitWidth + leftPadding + rightPadding
    implicitHeight: column.implicitHeight + topPadding + bottomPadding

    background: Rectangle {
        color: Theme.bgBase
        border.color: Theme.border
        border.width: 1
        radius: Theme.radius
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Theme.spacingLarge

        Label {
            id: titleLabel
            visible: root.title !== ""
            text: root.title
            color: Theme.textMuted
            font.bold: true
            font.pixelSize: Theme.fontSmall
        }
    }
}
