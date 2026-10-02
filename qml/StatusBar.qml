// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import OBSPuppeteer

Panel {
    id: root
    required property ObsClient obs

    function formatBitrate(kbps) {
        return kbps >= 1000 ? qsTr("%1 Mb/s").arg((kbps / 1000).toFixed(1))
                            : qsTr("%1 kb/s").arg(Math.round(kbps))
    }

    // Two columns when they fit, otherwise one, with the switch kept on the
    // right. Eliding the labels instead left them stuck short.
    GridLayout {
        id: strip

        Layout.fillWidth: true
        columnSpacing: Theme.paddingLarge
        rowSpacing: Theme.spacing

        readonly property real widthForOneLine:
            leftGroup.implicitWidth + studioModeButton.implicitWidth + columnSpacing

        columns: width >= widthForOneLine ? 2 : 1

        Row {
            id: leftGroup

            // Takes the slack, keeping the switch at the far right.
            Layout.fillWidth: true
            spacing: Theme.paddingLarge

            // "Close" rather than "Disconnect", which reads as stopping the stream.
            // The shape follows OBS Blade.
            ObsButton {
                id: closeButton
                objectName: "closeConnectionButton"
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Close")
                icon.source: Icons.close
                // Smaller than the text: OBS's X is a heavy glyph.
                icon.width: 10
                icon.height: 10
                font.pixelSize: Theme.fontSmall
                // Shorter than a full ObsButton, to fit the status strip.
                implicitHeight: 28
                onClicked: confirmClose.open()

                ToolTip.visible: hovered
                ToolTip.text: qsTr("Close this window's connection to OBS")
                ToolTip.delay: 500
            }

            Row {
                id: streamingRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingLarge

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    radius: 5
                    color: root.obs.streaming ? Theme.danger : Theme.textMuted
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.obs.streaming ? qsTr("LIVE %1").arg(root.obs.streamTimecode.substring(0, 8))
                                              : qsTr("Not streaming")
                    font.bold: root.obs.streaming
                    color: root.obs.streaming ? Theme.text : Theme.textMuted
                }
            }

            Row {
                id: recordingRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingLarge

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    radius: 5
                    // Red, like the Stop Recording button, rather than OBS's yellow.
                    color: root.obs.recording ? Theme.danger : Theme.textMuted
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.obs.recording ? qsTr("REC %1").arg(root.obs.recordTimecode.substring(0, 8))
                                              : qsTr("Not recording")
                    font.bold: root.obs.recording
                    color: root.obs.recording ? Theme.text : Theme.textMuted
                }
            }
        }

        // A toggle switch, since this turns a mode on and off.
        ObsToggleSwitch {
            id: studioModeButton
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            text: qsTr("Studio Mode")

            // A Binding, so OBS's answer restores the state after a toggle.
            Binding on checked {
                value: root.obs.studioModeEnabled
            }

            onToggled: root.obs.setStudioModeEnabled(checked)
        }
    }

    Dialog {
        id: confirmClose
        objectName: "confirmClose"

        // Drawn in the window, not as a separate compositor surface.
        popupType: Popup.Item

        // Fixed width: sizing it from its content, the status strip or the overlay
        // all caused binding loops. Fits the 400px minimum window width.
        width: 360

        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.CloseOnEscape
        title: qsTr("Close Connection")
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: root.obs.disconnectFromObs()

        // The button says what it does.
        Component.onCompleted: standardButton(Dialog.Ok).text = qsTr("Close")

        // The only background: the style's header and footer backgrounds would
        // stack different greys with seams.
        background: Rectangle {
            color: Theme.bgBase
            border.color: Theme.border
            border.width: 1
            radius: Theme.radius
        }

        header: Label {
            text: confirmClose.title
            color: Theme.text
            font.pixelSize: 18
            font.bold: true
            elide: Text.ElideRight
            padding: Theme.paddingLarge
            bottomPadding: Theme.padding
            background: null
        }

        footer: DialogButtonBox {
            // The default accent looks disabled on this background.
            Material.foreground: Theme.primaryLighter
            background: null
        }

        // The address in a fixed-width font, to stand out.
        contentItem: Label {
            objectName: "closeWarning"
            width: confirmClose.availableWidth
            wrapMode: Text.WordWrap
            color: Theme.text
            // RichText: StyledText ignores the font face.
            textFormat: Text.RichText
            text: qsTr("Close this window's connection to <font face='%1'>%2</font>? Anything OBS is streaming or recording keeps running.")
                  .arg(SystemFonts.fixedFamily)
                  .arg(root.obs.host + ":" + root.obs.port)
        }
    }

    // The stats line: OBS's performance, the recording folder and the About link.
    // Stream-only numbers are hidden when not streaming.
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingLarge

        // Hidden until OBS has answered, since "0 fps" would look like a reading.
        Label {
            objectName: "fpsLabel"
            visible: root.obs.statsKnown
            text: qsTr("%1 fps").arg(root.obs.activeFps.toFixed(0))
            color: Theme.textMuted
            font.pixelSize: Theme.fontSmall
        }

        Label {
            objectName: "cpuLabel"
            visible: root.obs.statsKnown
            text: qsTr("%1% CPU").arg(root.obs.cpuUsage.toFixed(1))
            color: Theme.textMuted
            font.pixelSize: Theme.fontSmall
        }

        Label {
            objectName: "bitrateLabel"
            visible: root.obs.streaming
            text: root.formatBitrate(root.obs.streamBitrateKbps)
            color: Theme.textMuted
            font.pixelSize: Theme.fontSmall
        }

        // Only while streaming, and only once frames have been skipped.
        Label {
            objectName: "skippedLabel"
            visible: root.obs.streaming && root.obs.streamSkippedFrames > 0
            text: qsTr("%1 skipped (%2%)").arg(root.obs.streamSkippedFrames)
                                          .arg(root.obs.streamSkippedPercent.toFixed(1))
            color: root.obs.streamSkippedPercent >= 1.0 ? Theme.danger : Theme.warning
            font.pixelSize: Theme.fontSmall
        }

        // The recording folder, which OBS keeps deep in Settings. The caption is a
        // separate label so the elide can't eat it.
        Label {
            objectName: "recordDirectoryCaption"
            visible: recordDirectoryLabel.visible
            text: qsTr("Recordings:")
            color: Theme.textMuted
            font.pixelSize: Theme.fontSmall
        }

        // Elided from the left, keeping the folder name. minimumWidth 0 lets the layout
        // shrink it. It takes the slack itself, so the path stays next to its caption.
        Label {
            id: recordDirectoryLabel
            objectName: "recordDirectoryLabel"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: root.obs.recordDirectory !== ""
            text: root.obs.recordDirectory
            color: Theme.textMuted
            font.pixelSize: Theme.fontSmall
            elide: Text.ElideLeft

            // For the tooltip, which shows only when the path is elided.
            HoverHandler {
                id: recordDirectoryHover
            }

            ToolTip {
                objectName: "recordDirectoryTip"
                parent: recordDirectoryLabel
                visible: recordDirectoryHover.hovered && recordDirectoryLabel.truncated
                delay: 500
                text: root.obs.recordDirectory
            }
        }

        // Takes the slack when there's no path, keeping About at the end.
        Item {
            Layout.fillWidth: true
            visible: root.obs.recordDirectory === ""
        }

        // At the end of the stats line: it's for bug reports, not live use. U+24D8
        // rather than U+2139, which many fonts draw as a plain "i".
        Label {
            objectName: "aboutLink"
            Layout.alignment: Qt.AlignVCenter
            text: "\u24D8 <u>" + qsTr("About") + "</u>"
            textFormat: Text.StyledText
            color: Theme.primaryLighter
            font.pixelSize: Theme.fontSmall

            Accessible.role: Accessible.Button
            Accessible.name: qsTr("About")

            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: aboutDialog.open()
            }
        }
    }

    AboutDialog {
        id: aboutDialog
    }
}
