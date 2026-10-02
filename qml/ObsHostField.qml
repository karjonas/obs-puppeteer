// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

// Bound, so the popup delegate resolves `control` at compile time.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import OBSPuppeteer

// The host box: type an address or pick a previous one, each marked with
// whether it's reachable (see ConnectionProbe). Styled like ObsComboBox
// rather than reusing it, because that one isn't editable.
ComboBox {
    id: control

    // The model holds {host, port} entries, most recent first. `reachable` is
    // ConnectionProbe's map; addresses not yet probed are absent.
    property var reachable: ({})

    // The × on an entry, or Shift+Delete on the highlighted one: forget that
    // address. The list stays open.
    signal removeRequested(int index)

    editable: true
    textRole: "host"

    // Sized by the text field: a fixed height cuts its floating label.
    implicitHeight: contentItem.implicitHeight
    // No padding: the text field spans the full width, like the fields below.
    // Both sides set because the style sets them individually.
    leftPadding: 0
    rightPadding: 0

    // Commits the highlighted entry as a click would, including `activated` so
    // the port comes along. Returns whether the list was open.
    function takeHighlighted() {
        if (!popup.visible)
            return false

        // The highlighted row; currentIndex is still the last committed one.
        const index = highlightedIndex >= 0 ? highlightedIndex : currentIndex
        popup.close()
        if (index >= 0) {
            currentIndex = index
            activated(index)
        }
        return true
    }

    function reachabilityOf(entry) {
        const answer = control.reachable[entry.host + ":" + entry.port]
        return answer === undefined ? null : answer
    }

    // A normal text field draws the box, so it matches the port and password
    // fields exactly.
    contentItem: TextField {
        text: control.editText
        placeholderText: qsTr("Host")
        color: Theme.text
        // Room for the arrow.
        rightPadding: control.indicator.width + 2 * Theme.paddingLarge
        // The combo box owns the value; this is only its editor.
        onTextEdited: control.editText = text

        // The editor has focus, so it handles the list's keys: Down opens and moves,
        // Return picks, Escape closes. With the list closed, Return means connect.
        Keys.onDownPressed: function (event) {
            if (control.popup.visible)
                control.incrementCurrentIndex()
            else
                control.popup.open()
            event.accepted = true
        }

        Keys.onUpPressed: function (event) {
            if (control.popup.visible)
                control.decrementCurrentIndex()
            event.accepted = control.popup.visible
        }

        Keys.onEscapePressed: function (event) {
            control.popup.close()
            event.accepted = control.popup.visible
        }

        // Shift+Delete, as in browsers; plain Delete still edits the text.
        Keys.onDeletePressed: function (event) {
            const index = control.highlightedIndex
            event.accepted = control.popup.visible && index >= 0
                    && (event.modifiers & Qt.ShiftModifier)
            if (event.accepted)
                control.removeRequested(index)
        }

        Keys.onReturnPressed: function (event) { event.accepted = control.takeHighlighted() }
        Keys.onEnterPressed: function (event) { event.accepted = control.takeHighlighted() }
    }

    indicator: Canvas {
        id: indicatorCanvas

        x: control.width - width - Theme.padding
        y: control.topPadding + (control.availableHeight - height) / 2
        width: 10
        height: 6
        contextType: "2d"
        // Above the text field, which would otherwise take its clicks.
        z: 1

        Connections {
            target: control
            function onPressedChanged() { indicatorCanvas.requestPaint() }
        }

        // Opens and closes the list. The editor covers the whole control, so
        // without this the mouse can't open it. The margin enlarges the target.
        TapHandler {
            margin: Theme.paddingLarge
            onTapped: control.popup.visible ? control.popup.close() : control.popup.open()
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

    // The text field draws the box.
    background: null

    delegate: ItemDelegate {
        id: item

        required property var modelData
        required property int index

        width: ListView.view.width
        highlighted: control.highlightedIndex === item.index

        contentItem: RowLayout {
            spacing: Theme.spacingLarge

            // Filled green: reachable. Hollow with a muted outline: unreachable.
            // Hollow with a lighter outline: not known yet.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                readonly property var live: control.reachabilityOf(item.modelData)
                color: live === true ? Theme.success : "transparent"
                border.width: live === true ? 0 : 1
                border.color: live === false ? Theme.textMuted : Theme.borderHover
            }

            Label {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: item.modelData.host
                color: Theme.text
                elide: Text.ElideRight
            }

            Label {
                Layout.alignment: Qt.AlignVCenter
                text: item.modelData.port
                color: Theme.textMuted
                font.pixelSize: Theme.fontSmall
            }

            // Forgets this address. Takes the press itself, so the row isn't
            // picked as well.
            ToolButton {
                id: forgetButton
                objectName: "forget_" + item.modelData.host + ":" + item.modelData.port
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 24
                implicitHeight: 24
                padding: 0
                focusPolicy: Qt.NoFocus
                icon.source: Icons.close
                icon.width: 10
                icon.height: 10
                icon.color: forgetButton.hovered ? Theme.danger : Theme.textMuted
                onClicked: control.removeRequested(item.index)

                // Its own hover circle, filling the button: Material's is sized and
                // placed for a 48px touch target and lands off-centre here.
                background: Rectangle {
                    radius: width / 2
                    color: forgetButton.hovered ? Theme.bgInputHover : "transparent"
                }

                Accessible.name: qsTr("Forget %1").arg(item.modelData.host)
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Forget this address")
                ToolTip.delay: 500
            }
        }

        background: Rectangle {
            color: (item.highlighted || control.currentIndex === item.index)
                   ? Theme.primary : "transparent"
            radius: Theme.radiusSmall
        }
    }

    popup: Popup {
        // Drawn in the window, not as a separate compositor surface.
        popupType: Popup.Item

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
            ScrollBar.vertical: ObsScrollBar {}
        }

        background: Rectangle {
            color: Theme.bgBase
            border.color: Theme.border
            border.width: 1
            radius: Theme.radius
        }
    }
}
