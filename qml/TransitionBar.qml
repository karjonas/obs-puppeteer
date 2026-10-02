// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

// Bound, so the ScenePreview instances resolve `root` at compile time.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import OBSPuppeteer

Panel {
    id: root
    required property ObsClient obs

    title: qsTr("STUDIO MODE")

    // Preview | controls | program, as in OBS. Each preview gets half of the
    // width the controls leave.
    readonly property int controlsWidth: 130
    readonly property real previewColumnWidth: Math.max(80, Math.floor((availableWidth - controlsWidth
                                                                        - 2 * Theme.paddingLarge) / 2))

    // Maximum picture height; the window sets it so the previews don't push
    // other panels off screen. Infinity means no limit; the window's budget can go
    // negative, meaning "as small as allowed".
    property real maximumPreviewHeight: Infinity

    // Minimum picture width, set by the window to a scene card's thumbnail width
    // so the preview is never smaller than a card.
    property real minimumPreviewWidth: 0

    // The larger of the two minimums, capped at the column width.
    readonly property real previewFloorWidth:
        Math.min(previewColumnWidth,
                 Math.max(minPreviewHeight * obs.videoAspect, minimumPreviewWidth))

    readonly property real previewWidth: {
        // A budget below the minimum still means "use the minimum".
        const fromHeight = Math.max(minPreviewHeight, maximumPreviewHeight) * obs.videoAspect
        return Math.max(previewFloorWidth, Math.min(previewColumnWidth, fromHeight))
    }
    // Floored, to stay within the budget.
    readonly property int previewHeight: Math.floor(previewWidth / obs.videoAspect)

    readonly property int minPreviewHeight: 48

    // Height of everything except the pictures; the window subtracts it from its
    // budget.
    readonly property real nonPreviewHeight: chromeHeight + Theme.spacingSmall + previewSide.nameHeight

    function thumbnailFor(sceneName) {
        return obs.thumbnails[sceneName] || ""
    }

    component ScenePreview: ColumnLayout {
        id: preview

        property alias label: badge.text
        property alias badgeColor: badgeBackground.color
        property string sceneName: ""
        property alias sourceImage: image.source
        readonly property alias nameHeight: nameLabel.height

        spacing: Theme.spacingSmall

        Rectangle {
            // Capped at the picture's size and centred, so a height-limited picture
            // doesn't sit in a wide empty box.
            Layout.fillWidth: true
            Layout.maximumWidth: root.previewWidth
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.preferredHeight: root.previewHeight
            Layout.maximumHeight: root.previewHeight
            Layout.minimumHeight: root.minPreviewHeight
            color: Theme.bgPreview
            radius: Theme.radiusSmall
            clip: true

            // Letterboxed to the canvas aspect.
            ThumbnailImage {
                id: image
                anchors.centerIn: parent
                readonly property bool boxIsWide: parent.width / parent.height > root.obs.videoAspect
                width: boxIsWide ? parent.height * root.obs.videoAspect : parent.width
                height: boxIsWide ? parent.height : parent.width / root.obs.videoAspect
            }

            Label {
                id: badge
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Theme.spacingSmall
                color: Theme.text
                font.bold: true
                font.pixelSize: Theme.fontXSmall
                padding: Theme.spacingSmall
                background: Rectangle {
                    id: badgeBackground
                    radius: Theme.radiusSmall
                }
            }
        }

        Label {
            id: nameLabel
            Layout.fillWidth: true
            text: preview.sceneName
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: Theme.textMuted
            font.pixelSize: Theme.fontSmall
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Theme.paddingLarge

        ScenePreview {
            // Named so the panel can measure the name label; both sides match.
            id: previewSide
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            label: qsTr("PREVIEW")
            badgeColor: Theme.success
            sceneName: root.obs.previewScene
            sourceImage: root.thumbnailFor(root.obs.previewScene)
        }

        // Fixed width, centred. fillWidth defaults to true for nested layouts, which
        // would squeeze the previews.
        ColumnLayout {
            Layout.fillWidth: false
            Layout.preferredWidth: root.controlsWidth
            Layout.maximumWidth: root.controlsWidth
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacingLarge

            ObsComboBox {
                Layout.fillWidth: true
                model: root.obs.transitions
                currentIndex: root.obs.transitions.indexOf(root.obs.currentTransition)
                onActivated: root.obs.setCurrentTransition(currentText)
            }

            ObsButton {
                Layout.fillWidth: true
                text: qsTr("Transition")
                onClicked: root.obs.triggerStudioModeTransition()
            }
        }

        ScenePreview {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            label: qsTr("LIVE")
            badgeColor: Theme.danger
            sceneName: root.obs.currentProgramScene
            sourceImage: root.thumbnailFor(root.obs.currentProgramScene)
        }
    }
}
