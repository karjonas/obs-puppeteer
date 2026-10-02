// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import OBSPuppeteer

ApplicationWindow {
    id: window
    width: 520
    height: 880
    minimumWidth: 400
    // The panels scroll when they don't fit, so the window can be this short.
    minimumHeight: 320
    visible: true
    title: qsTr("OBS Puppeteer")
    color: Theme.bgWindow

    // OBS's own dark theme, not the OS setting. See Theme.qml.
    Material.theme: Material.Dark
    // Control fill, not the window background.
    Material.background: Theme.bgInput
    Material.foreground: Theme.text
    Material.primary: Theme.primary
    Material.accent: Theme.primaryLight

    // Set by main.cpp from the command line.
    property string cliHost: ""
    property int cliPort: 4455
    property string cliPassword: ""

    ObsClient {
        id: obs
    }

    // Thumbnail width to request: the widest box one is drawn in, in device
    // pixels. See ObsClient::previewWidth.
    Binding {
        target: obs
        property: "previewWidth"
        // Wait for layout, or the first thumbnails are fetched at the minimum size.
        when: scenesPanel.width > 0
        value: Math.round(Math.max(scenesPanel.thumbnailWidth,
                                   transitionBar.visible ? transitionBar.previewWidth : 0)
                          * window.Screen.devicePixelRatio)
    }

    Component.onCompleted: {
        if (window.cliHost.length > 0)
            obs.connectToObs(window.cliHost, window.cliPort, window.cliPassword)
    }

    ConnectionView {
        id: connectionView
        anchors.fill: parent
        visible: obs.connectionState !== ObsClient.Authenticated
        obs: obs
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.paddingLarge
        spacing: Theme.paddingLarge
        visible: obs.connectionState === ObsClient.Authenticated

        StatusBar {
            Layout.fillWidth: true
            Layout.minimumHeight: implicitHeight
            obs: obs
        }

        // The panels scroll; the status strip and the buttons below don't. This is the
        // window's only vertical scroll bar: every panel shows all its content.
        //
        // A Flickable because a ScrollView can't infer the extent of a ColumnLayout
        // with an explicit height, and misplaces its scroll bar.
        Flickable {
            id: panelScroll
            objectName: "panelScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            contentWidth: width
            contentHeight: panels.height
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ObsScrollBar {}

            ColumnLayout {
                id: panels
                width: panelScroll.width
                // At least the viewport's height, so no gap shows below the panels.
                height: Math.max(panelScroll.height, naturalHeight)
                spacing: Theme.paddingLarge

                // Full height of the visible panels plus the gaps between them.
                readonly property real naturalHeight:
                    (transitionBar.visible ? transitionBar.implicitHeight + spacing : 0)
                    + scenesPanel.implicitHeight + spacing
                    + listPanels.implicitHeight

                // Sources and audio share a row. The mixer gets the width its
                // channels need, capped so the source list keeps minSourcesWidth,
                // or at half the row if that's more. Squeezed, it scrolls sideways.
                readonly property int minSourcesWidth: 280
                // The width both panels share: the row minus the gap between them.
                readonly property real listPanelsWidth: panels.width - Theme.paddingLarge
                readonly property real mixerWidth:
                    Math.min(audioPanel.naturalWidth,
                             Math.max(Math.floor(listPanelsWidth / 2),
                                      listPanelsWidth - minSourcesWidth))

                // Maximum height for the studio preview pictures: what's left after
                // the other panels and the transition bar's own chrome. The previews
                // grow with the width, so without this they'd crowd out the other
                // panels. Negative means "as small as allowed".
                readonly property real studioPreviewBudget:
                    panelScroll.height - naturalHeightBelowStudio
                    - transitionBar.nonPreviewHeight - spacing

                readonly property real naturalHeightBelowStudio:
                    scenesPanel.implicitHeight + spacing
                    + listPanels.implicitHeight

                TransitionBar {
                    id: transitionBar
                    objectName: "transitionBar"
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    maximumPreviewHeight: panels.studioPreviewBudget
                    // At least as large as a scene card's thumbnail.
                    minimumPreviewWidth: scenesPanel.thumbnailWidth
                    visible: obs.studioModeEnabled
                    obs: obs
                }

                // Takes any spare height. Its minimum is the full grid, so cards never
                // clip.
                ScenesPanel {
                    id: scenesPanel
                    objectName: "scenesPanel"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: implicitHeight
                    Layout.minimumHeight: implicitHeight
                    // The preview's column width, not the picture's: the picture
                    // depends on this panel's height, which would make a binding
                    // loop. No cap outside Studio Mode.
                    maxCardWidth: transitionBar.visible ? transitionBar.previewColumnWidth
                                                        : Infinity
                    obs: obs
                }

                // Both fill the taller one's height, so the row shares top and bottom
                // edges.
                RowLayout {
                    id: listPanels
                    Layout.fillWidth: true
                    spacing: Theme.paddingLarge

                    SourcesPanel {
                        id: sourcesPanel
                        objectName: "sourcesPanel"
                        // Whatever the mixer doesn't take.
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        Layout.fillHeight: true
                        obs: obs
                    }

                    AudioPanel {
                        id: audioPanel
                        objectName: "audioPanel"
                        // See panels.mixerWidth.
                        Layout.fillWidth: false
                        Layout.preferredWidth: panels.mixerWidth
                        Layout.preferredHeight: implicitHeight
                        Layout.fillHeight: true
                        obs: obs
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.paddingLarge

            // Checked while active, like OBS's own buttons, but red rather than blue:
            // red is what this window uses for anything live.
            ObsButton {
                objectName: "streamButton"
                Layout.fillWidth: true
                text: obs.streaming ? qsTr("Stop Streaming") : qsTr("Start Streaming")
                checked: obs.streaming
                accent: Theme.danger
                accentLight: Theme.dangerLight
                accentLighter: Theme.dangerLighter
                onClicked: obs.toggleStream()
            }

            ObsButton {
                Layout.fillWidth: true
                text: obs.recording ? qsTr("Stop Recording") : qsTr("Start Recording")
                checked: obs.recording
                accent: Theme.danger
                accentLight: Theme.dangerLight
                accentLighter: Theme.dangerLighter
                onClicked: obs.toggleRecord()
            }
        }
    }
}
