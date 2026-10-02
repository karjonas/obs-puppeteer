// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

// Bound, so the channel delegates resolve `root` at compile time and take
// their model data as a declared property.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import OBSPuppeteer

Panel {
    id: root
    required property ObsClient obs

    title: qsTr("AUDIO")

    // OBS's vertical mixer layout: one column per input, so the panel's height
    // doesn't grow with the number of inputs. Too many inputs scroll sideways.
    readonly property int channelWidth: 92
    // Room for the ruler's eleven labels without them touching.
    readonly property int meterHeight: 154

    // Set explicitly because the panel's height is built from them.
    readonly property int nameHeight: 16
    readonly property int readoutHeight: 14
    readonly property int muteButtonHeight: 28

    readonly property int channelHeight: nameHeight + Theme.spacingSmall
                                         + readoutHeight + Theme.spacingSmall
                                         + meterHeight + Theme.spacingSmall
                                         + muteButtonHeight

    readonly property int chromeWidth: leftPadding + rightPadding

    // Width with every channel visible; the window uses it to decide how to share
    // the row with the source list.
    readonly property int naturalWidth:
        Math.max(1, root.obs.inputs.length) * channelWidth
        + Math.max(0, root.obs.inputs.length - 1) * list.spacing
        + chromeWidth

    // Formatted like OBS's VolumeControl::updateText, including "-inf dB".
    function formatVolumeDb(db) {
        return db < -96 ? qsTr("-inf dB") : qsTr("%1 dB").arg(db.toFixed(1))
    }

    ListView {
        id: list
        objectName: "audioList"
        orientation: ListView.Horizontal
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.obs.inputs
        spacing: Theme.spacingLarge

        // A ListView has no implicit height.
        implicitHeight: root.channelHeight

        // Sideways only; the window scrolls vertically.
        ScrollBar.horizontal: ObsScrollBar {}

        delegate: ColumnLayout {
            id: channel
            required property var modelData

            height: ListView.view.height
            width: root.channelWidth
            spacing: Theme.spacingSmall

            readonly property bool muted: root.obs.inputMuted[channel.modelData.inputName] === true
            readonly property real volumeDb: root.obs.inputVolumes[channel.modelData.inputName] || 0

            Label {
                Layout.fillWidth: true
                Layout.preferredHeight: root.nameHeight
                text: channel.modelData.inputName
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                color: Theme.text
                font.pixelSize: Theme.fontSmall

                ToolTip.visible: nameHover.hovered && truncated
                ToolTip.text: channel.modelData.inputName
                ToolTip.delay: 500

                HoverHandler { id: nameHover }
            }

            // Follows the handle while dragging, as OBS does; otherwise shows what OBS
            // reports, which is how "-inf dB" appears (the fader stops at -60).
            Label {
                Layout.fillWidth: true
                Layout.preferredHeight: root.readoutHeight
                text: root.formatVolumeDb(fader.pressed ? fader.value : channel.volumeDb)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: Theme.textMuted
                font.pixelSize: Theme.fontSmall
            }

            // Fader, meter, ruler, as in OBS's vertical mixer.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.meterHeight
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.spacingSmall

                Slider {
                    id: fader
                    objectName: "fader_" + channel.modelData.inputName
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignHCenter
                    orientation: Qt.Vertical
                    from: -60
                    to: 0
                    value: channel.volumeDb
                    onMoved: root.obs.setInputVolumeDb(channel.modelData.inputName, value)
                }

                // One bar per audio channel, a pixel apart, as OBS draws them.
                Row {
                    id: meters
                    objectName: "meters_" + channel.modelData.inputName
                    Layout.fillHeight: true
                    spacing: 1

                    readonly property var levels: root.obs.inputLevels[channel.modelData.inputName]
                    // At least one, so a muted or idle input still shows a meter.
                    readonly property int channelCount:
                        (meters.levels && meters.levels.length > 0) ? meters.levels.length : 1

                    // Modelled on the channel count, not the levels: the levels arrive
                    // as a new array ~20 times a second, which would rebuild every bar.
                    Repeater {
                        model: meters.channelCount

                        delegate: LevelMeter {
                            id: bar
                            required property int index

                            readonly property var level:
                                (meters.levels && index < meters.levels.length)
                                    ? meters.levels[index] : null

                            objectName: "meter_" + channel.modelData.inputName + "_" + index
                            height: meters.height
                            orientation: Qt.Vertical
                            peak: bar.level ? bar.level.peak : 0
                            magnitude: bar.level ? bar.level.magnitude : 0
                            muted: channel.muted
                        }
                    }
                }

                MeterScale {
                    objectName: "scale_" + channel.modelData.inputName
                    Layout.fillHeight: true
                }
            }

            // OBS's own icon pairing for this button. See Icons.qml.
            ToolButton {
                objectName: "muteButton_" + channel.modelData.inputName
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: root.muteButtonHeight
                icon.source: channel.muted ? Icons.mute : Icons.audio
                icon.color: channel.muted ? Theme.danger : Theme.text
                icon.width: 16
                icon.height: 16
                onClicked: root.obs.toggleInputMute(channel.modelData.inputName)

                ToolTip.visible: hovered
                ToolTip.text: channel.muted ? qsTr("Unmute") : qsTr("Mute")
                ToolTip.delay: 500
            }
        }

        Label {
            anchors.centerIn: parent
            visible: root.obs.inputs.length === 0
            text: qsTr("No audio inputs found")
            color: Theme.textMuted
        }
    }
}
