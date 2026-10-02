// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

// Bound, so the row delegates resolve `root` at compile time and take their
// model data as a declared property.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import OBSPuppeteer

Panel {
    id: root
    required property ObsClient obs

    title: qsTr("SOURCES")

    // Tall enough for every row; the window scrolls, not the panel.
    readonly property int rowHeight: 32
    // At least one row, so the "no sources" line has room.
    readonly property int visibleRows: Math.max(1, root.obs.sources.length)

    function heightForRows(rows) {
        return rows * rowHeight + Math.max(0, rows - 1) * Theme.spacingSmall
    }

    ListView {
        id: list
        objectName: "sourceList"
        Layout.fillWidth: true
        Layout.fillHeight: true
        model: root.obs.sources
        spacing: Theme.spacingSmall

        // A ListView has no implicit height.
        implicitHeight: root.heightForRows(root.visibleRows)

        // Not interactive, so it doesn't swallow the window's scrolling.
        interactive: false

        delegate: RowLayout {
            id: sourceRow
            required property var modelData

            width: ListView.view.width
            height: root.rowHeight

            readonly property bool sourceVisible: root.obs.sourceVisibility[String(sourceRow.modelData.sceneItemId)] === true

            // Holds no state of its own, so changes made in OBS just flow through.
            ToolButton {
                objectName: "visibilityToggle_" + sourceRow.modelData.sourceName
                icon.source: sourceRow.sourceVisible ? Icons.visible : Icons.invisible
                icon.color: sourceRow.sourceVisible ? Theme.text : Theme.textMuted
                icon.width: 16
                icon.height: 16
                onClicked: root.obs.setSceneItemEnabled(root.obs.currentProgramScene,
                                                        sourceRow.modelData.sceneItemId,
                                                        !sourceRow.sourceVisible)

                ToolTip.visible: hovered
                ToolTip.text: sourceRow.sourceVisible ? qsTr("Hide") : qsTr("Show")
                ToolTip.delay: 500
            }

            Label {
                Layout.fillWidth: true
                text: sourceRow.modelData.sourceName
                elide: Text.ElideRight
                color: Theme.text
            }
        }

        Label {
            anchors.centerIn: parent
            visible: root.obs.sources.length === 0
            text: qsTr("No sources in this scene")
            color: Theme.textMuted
        }
    }
}
