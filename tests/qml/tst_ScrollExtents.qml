// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// A panel with more than fits must ask for its full height, or the overflow is
// clipped silently. The scene grid's cards wrap onto several rows, and the panel
// has to ask for all of them.
TestCase {
    id: testCase
    name: "ScrollExtents"
    width: 420
    height: 300
    // Shown, since unshown items report themselves invisible.
    visible: true
    when: windowShown

    readonly property int sceneCount: 12

    MockObsServerQml {
        id: mockServer

        onRequestReceived: (requestType, requestId, requestData) => {
            if (requestType === "GetSceneList") {
                let scenes = []
                for (let i = 0; i < testCase.sceneCount; ++i)
                    scenes.push({ sceneName: "Scene " + (i + 1), sceneIndex: i })
                sendRequestResponse(requestId, true, {
                    currentProgramSceneName: "Scene 1",
                    scenes: scenes
                })
            } else {
                sendRequestResponse(requestId, true, {})
            }
        }
    }

    ObsClient {
        id: obs
    }

    ScenesPanel {
        id: panel
        width: 420
        // Given the height it asks for.
        height: panel.implicitHeight
        obs: obs
    }

    function initTestCase() {
        verify(mockServer.start())
        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.connectionState === ObsClient.Authenticated })
        tryVerify(function() { return obs.scenes.length === testCase.sceneCount })
    }

    function test_the_grid_asks_for_every_row_it_wrapped_to() {
        const grid = findChild(panel, "sceneGrid")
        verify(grid !== null)

        // Twelve cards wrap to several rows at this width.
        tryVerify(function() { return grid.implicitHeight > panel.cardHeight })

        // The last card is within the requested height.
        const last = findChild(panel, "sceneCard_Scene " + sceneCount)
        verify(last !== null)
        const bottom = last.mapToItem(grid, 0, last.height).y
        verify(bottom <= grid.height + 1,
               "last card at " + bottom + " is past the panel's height " + grid.height)
    }

    // No scroller inside the panel; the window scrolls.
    function test_the_grid_does_not_scroll_itself() {
        const grid = findChild(panel, "sceneGrid")
        verify(grid.contentHeight === undefined)
        verify(grid.ScrollBar === undefined || grid.ScrollBar.vertical === null)
    }
}
