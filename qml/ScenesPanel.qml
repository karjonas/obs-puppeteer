// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

// Bound, so the card delegates resolve `root` at compile time.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import OBSPuppeteer

Panel {
    id: root
    required property ObsClient obs

    title: qsTr("SCENES")

    // Card height follows its width and the canvas aspect. The band between the
    // minimum and maximum widths is kept narrow, so cards don't jump much in
    // size when a column is added.
    readonly property int minCardWidth: 180
    // Beyond this width a new column is added instead.
    readonly property int cardWidthCeiling: 220
    // In Studio Mode the window lowers this to the preview column's width, so a
    // card is never bigger than the preview.
    property real maxCardWidth: Infinity
    readonly property real cardCeiling: Math.min(maxCardWidth, cardWidthCeiling)
    readonly property int cardPadding: Theme.spacing
    readonly property int labelHeight: 18
    // Studio Mode can set the maximum below the minimum.
    readonly property real columnWidth: Math.min(minCardWidth, cardCeiling)
    // The panel's width, not the flow's, which depends on this. At most one column
    // per scene, so cards aren't shrunk to make room for empty columns.
    readonly property int cardColumns: Math.max(1, Math.min(
        Math.floor((grid.width + Theme.spacing) / (columnWidth + Theme.spacing)),
        root.obs.scenes.length))
    // Floored, or rounding can wrap the last card and make the layout jitter
    // while resizing. The maximum wins over the 120px minimum.
    readonly property real cardWidth: Math.min(root.cardCeiling, Math.max(120,
        Math.floor((grid.width - (cardColumns - 1) * Theme.spacing) / cardColumns)))

    // Width of a full row. Cards are left-aligned, so any leftover space is on
    // the right.
    readonly property real rowWidth: cardColumns * cardWidth
                                     + (cardColumns - 1) * Theme.spacing
    readonly property real cardHeight: Math.round((cardWidth - 2 * cardPadding) / obs.videoAspect)
                                       + 2 * cardPadding + Theme.spacingSmall + labelHeight
    // The thumbnail's width; the window uses it to size thumbnail requests.
    readonly property real thumbnailWidth: cardWidth - 2 * cardPadding

    // A plain Item: the window's scroll bar handles overflow.
    Item {
        id: grid
        objectName: "sceneGrid"
        Layout.fillWidth: true
        Layout.fillHeight: true

        // Height of all the rows.
        implicitHeight: flow.height
        // Layout hints for the enclosing ColumnLayout.
        Layout.preferredHeight: flow.height
        Layout.minimumHeight: flow.height

        Flow {
            id: flow
            width: root.rowWidth
            spacing: Theme.spacing

            Repeater {
                model: root.obs.scenes

                delegate: Rectangle {
                    id: card
                    required property var modelData

                    readonly property bool isProgram: modelData.sceneName === root.obs.currentProgramScene
                    readonly property bool isPreview: root.obs.studioModeEnabled && modelData.sceneName === root.obs.previewScene
                    readonly property string thumbnail: root.obs.thumbnails[modelData.sceneName] || ""

                    objectName: "sceneCard_" + modelData.sceneName
                    implicitWidth: root.cardWidth
                    implicitHeight: root.cardHeight
                    radius: Theme.radius
                    color: (isProgram || isPreview) ? Theme.bgInput : Theme.bgWindow
                    border.width: (isProgram || isPreview) ? 2 : 1
                    border.color: isProgram ? Theme.danger
                                             : isPreview ? Theme.success
                                                          : Theme.border

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: root.cardPadding
                        spacing: Theme.spacingSmall

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Theme.bgPreview
                            radius: Theme.radiusSmall
                            clip: true

                            ThumbnailImage {
                                anchors.centerIn: parent
                                height: parent.height
                                width: Math.min(parent.width, height * root.obs.videoAspect)
                                source: card.thumbnail
                            }

                            Label {
                                anchors.centerIn: parent
                                visible: !card.thumbnail
                                text: qsTr("No preview")
                                color: Theme.textMuted
                                font.pixelSize: Theme.fontSmall
                            }

                            Label {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: Theme.spacingSmall
                                visible: card.isProgram || card.isPreview
                                text: card.isProgram ? qsTr("LIVE") : qsTr("PREVIEW")
                                color: Theme.text
                                font.bold: true
                                font.pixelSize: Theme.fontXSmall
                                padding: Theme.spacingSmall
                                background: Rectangle {
                                    color: card.isProgram ? Theme.danger : Theme.success
                                    radius: Theme.radiusSmall
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.labelHeight
                            text: card.modelData.sceneName
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            font.bold: card.isProgram || card.isPreview
                            font.pixelSize: Theme.fontSmall
                            color: (card.isProgram || card.isPreview) ? Theme.text : Theme.textMuted
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (root.obs.studioModeEnabled)
                                root.obs.setCurrentPreviewScene(card.modelData.sceneName)
                            else
                                root.obs.setCurrentProgramScene(card.modelData.sceneName)
                        }
                    }

                    ToolTip.visible: hoverHandler.hovered
                    ToolTip.text: card.modelData.sceneName
                    ToolTip.delay: 500

                    HoverHandler {
                        id: hoverHandler
                    }
                }
            }
        }
    }
}
