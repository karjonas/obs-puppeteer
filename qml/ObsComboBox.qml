// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

// Bound, so the popup delegate resolves `control` at compile time.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import OBSPuppeteer

// A combo box drawn like OBS's QComboBox. Material's ignores
// Material.background and comes out white on this palette.
ComboBox {
    id: control

    implicitHeight: 34
    leftPadding: Theme.paddingLarge
    rightPadding: indicator.width + Theme.padding

    Layout.minimumHeight: implicitHeight

    contentItem: Label {
        text: control.displayText
        font: control.font
        color: control.enabled ? Theme.text : Theme.textMuted
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Canvas {
        id: indicatorCanvas

        x: control.width - width - Theme.padding
        y: control.topPadding + (control.availableHeight - height) / 2
        width: 10
        height: 6
        contextType: "2d"

        Connections {
            target: control
            function onPressedChanged() { indicatorCanvas.requestPaint() }
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.moveTo(0, 0)
            ctx.lineTo(width, 0)
            ctx.lineTo(width / 2, height)
            ctx.closePath()
            ctx.fillStyle = control.enabled ? Theme.text : Theme.textMuted
            ctx.fill()
        }
    }

    background: Rectangle {
        color: control.enabled ? Theme.bgInput : Theme.bgInputDisabled
        border.width: 1
        border.color: (control.hovered || control.visualFocus) ? Theme.borderHover : Theme.bgInput
        radius: Theme.radius
    }

    delegate: ItemDelegate {
        id: item

        required property var modelData
        required property int index

        width: ListView.view.width
        highlighted: control.highlightedIndex === item.index

        contentItem: Label {
            text: item.modelData
            color: Theme.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            color: (item.highlighted || control.currentIndex === item.index) ? Theme.primary : "transparent"
            radius: Theme.radiusSmall
        }
    }

    popup: Popup {
        // A gap, so the two outlines don't merge.
        y: control.height + Theme.spacingSmall
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 2 * Theme.padding, 300)
        // More than the corner radius, so highlighted rows don't clip the corners.
        padding: Theme.padding

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.delegateModel
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }

        background: Rectangle {
            color: Theme.bgBase
            border.color: Theme.border
            border.width: 1
            radius: Theme.radius
        }
    }
}
