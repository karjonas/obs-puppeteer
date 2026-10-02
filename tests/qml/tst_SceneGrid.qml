// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// Scene cards while resizing: the band between the minimum and maximum card
// width stays narrow, the cards always fit their row, and leftover space goes
// to the right.
TestCase {
    id: testCase
    name: "SceneGrid"
    width: 600
    height: 400
    visible: true
    when: windowShown

    readonly property int sceneCount: 8

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
            } else if (requestType === "GetVideoSettings") {
                sendRequestResponse(requestId, true, { baseWidth: 1920, baseHeight: 1080 })
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
        width: 600
        height: panel.implicitHeight
        obs: obs
    }

    function initTestCase() {
        verify(mockServer.start())
        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.connectionState === ObsClient.Authenticated })
        tryVerify(function() { return obs.scenes.length === testCase.sceneCount })
    }

    // Every width from narrowest to maximised, waiting for layout after each.
    function sweep(check) {
        const grid = findChild(panel, "sceneGrid")
        verify(grid !== null)

        for (let w = 360; w <= 1400; w += 8) {
            panel.width = w
            const expected = w - panel.leftPadding - panel.rightPadding
            tryVerify(function() { return grid.width === expected })
            check(grid, w)
        }
    }

    function test_cards_stay_inside_their_band() {
        sweep(function(grid, w) {
            verify(panel.cardWidth >= panel.minCardWidth,
                   "at " + w + " the cards fell to " + panel.cardWidth
                   + ", under the " + panel.minCardWidth + " floor")
            verify(panel.cardWidth <= panel.maxCardWidth,
                   "at " + w + " the cards grew to " + panel.cardWidth
                   + ", over the " + panel.maxCardWidth + " cap")
        })
    }

    // No resize step changes the card width by more than 40px, so cards don't
    // visibly jump when a column is added.
    function test_no_step_of_the_resize_moves_a_card_far() {
        let previous = 0
        let worst = 0
        let worstAt = 0

        sweep(function(grid, w) {
            if (previous > 0 && Math.abs(panel.cardWidth - previous) > worst) {
                worst = Math.abs(panel.cardWidth - previous)
                worstAt = w
            }
            previous = panel.cardWidth
        })

        verify(worst <= 40, "cards moved " + worst + "px at a width of " + worstAt)
    }

    // A row wider than the grid wraps its last card, which can make layout jitter.
    function test_a_row_of_cards_fits_the_grid() {
        sweep(function(grid, w) {
            verify(panel.rowWidth <= grid.width + 1,
                   "at " + w + " a row of " + panel.cardColumns + " wants "
                   + panel.rowWidth + " from a grid of " + grid.width)
        })
    }

    // No columns without a scene in them.
    function test_no_column_is_left_empty() {
        const grid = findChild(panel, "sceneGrid")
        const was = panel.width

        // Room for more columns than scenes.
        panel.width = 1800
        tryVerify(function() { return grid.width === 1800 - panel.leftPadding - panel.rightPadding })

        compare(panel.cardColumns, testCase.sceneCount)
        verify(panel.rowWidth <= grid.width + 1)

        panel.width = was
    }

    // Eight cards at 220px don't fill 1400px; the leftover goes to the right,
    // keeping the first card aligned with the panel's title.
    function test_the_cards_start_at_the_panels_edge() {
        sweep(function(grid, w) {
            const flow = grid.children[0]
            compare(flow.x, 0, "at " + w + " the grid does not start at the edge")
        })
    }
}
