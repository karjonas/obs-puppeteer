// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// A window with room for everything shows no scroll bar. The studio previews
// grow with width, so they're bounded by the height the other panels leave.
TestCase {
    id: testCase
    name: "WideWindow"
    when: windowShown

    // A modest setup that fits on a 1080p screen.
    readonly property int sceneCount: 4
    readonly property int inputCount: 3
    readonly property int sourceCount: 4

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
            } else if (requestType === "GetStudioModeEnabled") {
                sendRequestResponse(requestId, true, { studioModeEnabled: true })
            } else if (requestType === "GetCurrentPreviewScene") {
                sendRequestResponse(requestId, true, { currentPreviewSceneName: "Scene 2" })
            } else if (requestType === "GetInputList") {
                let inputs = []
                for (let i = 0; i < testCase.inputCount; ++i)
                    inputs.push({ inputName: "Input " + (i + 1), inputKind: "pulse_input_capture" })
                sendRequestResponse(requestId, true, { inputs: inputs })
            } else if (requestType === "GetSceneItemList") {
                let items = []
                for (let i = 0; i < testCase.sourceCount; ++i) {
                    items.push({
                        sourceName: "Source " + (i + 1),
                        sceneItemId: i + 1,
                        inputKind: "browser_source",
                        sceneItemEnabled: true
                    })
                }
                sendRequestResponse(requestId, true, { sceneItems: items })
            } else {
                sendRequestResponse(requestId, true, {})
            }
        }
    }

    Component {
        id: windowComponent

        Main {
            visible: true
            width: 1920
            height: 1080
            cliHost: "127.0.0.1"
            cliPort: mockServer.port
        }
    }

    property var window: null

    function initTestCase() {
        verify(mockServer.start())
        window = windowComponent.createObject(null)
        verify(window !== null)
        tryVerify(function() {
            const audio = findChild(window, "audioList")
            const bar = findChild(window, "transitionBar")
            return audio !== null && audio.count === testCase.inputCount
                && bar !== null && bar.visible
        })
    }

    function cleanupTestCase() {
        if (window !== null)
            window.destroy()
    }

    function test_a_window_with_room_for_everything_does_not_scroll() {
        const scroll = findChild(window, "panelScroll")
        verify(scroll !== null)

        tryVerify(function() { return scroll.contentHeight <= scroll.height + 1 })
        // A full-size handle means nothing to scroll.
        tryVerify(function() { return scroll.ScrollBar.vertical.size >= 1 })
    }

    function test_the_previews_give_up_the_height_that_buys_it() {
        const bar = findChild(window, "transitionBar")

        // Width alone would make the preview taller than the budget allows.
        const heightFromWidthAlone = bar.previewColumnWidth / 1.7777777777777777
        verify(bar.maximumPreviewHeight < heightFromWidthAlone,
               "budget " + bar.maximumPreviewHeight + " is not the binding limit against "
               + heightFromWidthAlone)

        // Within the budget.
        verify(bar.previewHeight <= bar.maximumPreviewHeight + 1,
               "preview is " + bar.previewHeight + ", budget was " + bar.maximumPreviewHeight)

        // Not below the minimum or a scene card.
        verify(bar.previewHeight >= bar.minPreviewHeight)
        verify(bar.previewWidth >= bar.minimumPreviewWidth)

        // Still the canvas aspect.
        fuzzyCompare(bar.previewWidth / bar.previewHeight, 1.7777777777777777, 0.05)
    }

    // A scene card is never larger than the studio preview.
    function test_no_scene_card_outgrows_the_scene_going_live() {
        const bar = findChild(window, "transitionBar")
        const scenes = findChild(window, "scenesPanel")
        const scroll = findChild(window, "panelScroll")
        const was = window.width

        for (let w = 400; w <= 1400; w += 20) {
            window.width = w
            const viewport = w - 2 * Theme.paddingLarge
            tryVerify(function() { return scroll.width === viewport })
            wait(0)

            verify(scenes.thumbnailWidth <= bar.previewWidth + 1,
                   "at " + w + " a card thumbnail is " + scenes.thumbnailWidth
                   + " against a live preview of " + bar.previewWidth)
        }

        window.width = was
    }

    // Wide but short: the budget is exhausted while the width would allow huge
    // previews. A negative budget must mean "minimum", not "no limit".
    function test_the_previews_fall_to_their_floor_when_the_window_is_too_short() {
        const bar = findChild(window, "transitionBar")
        const wasHeight = window.height

        window.height = 600
        tryVerify(function() { return bar.maximumPreviewHeight < bar.minPreviewHeight })

        // Still 1920 wide.
        verify(bar.previewColumnWidth / 1.7777777777777777 > 4 * bar.minPreviewHeight)
        // At its floor: the larger of its own minimum and a scene card.
        fuzzyCompare(bar.previewHeight,
                     Math.floor(bar.previewFloorWidth / 1.7777777777777777), 1)

        // Wait for the budget, not the picture, so the next test doesn't start
        // mid-resize.
        window.height = wasHeight
        tryVerify(function() { return bar.maximumPreviewHeight >= bar.previewHeight })
    }

    // The budget covers the picture only; the panel's chrome comes out first.
    function test_the_panel_fits_the_budget_it_was_given() {
        const bar = findChild(window, "transitionBar")
        verify(bar.nonPreviewHeight > 0)
        verify(bar.implicitHeight <= bar.nonPreviewHeight + bar.previewHeight + 1,
               "panel is " + bar.implicitHeight + " for a " + bar.previewHeight
               + " preview plus " + bar.nonPreviewHeight + " of chrome")
    }
}
