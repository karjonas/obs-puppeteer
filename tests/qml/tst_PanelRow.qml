// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// How the sources list and the mixer split their shared row at every width.
// The mixer needs whole 92px channels; the list takes any width.
TestCase {
    id: testCase
    name: "PanelRow"
    when: windowShown

    readonly property int inputCount: 3
    readonly property real aspect: 1.7777777777777777

    MockObsServerQml {
        id: mockServer

        onRequestReceived: (requestType, requestId, requestData) => {
            if (requestType === "GetSceneList") {
                sendRequestResponse(requestId, true, {
                    currentProgramSceneName: "Scene 1",
                    scenes: [{ sceneName: "Scene 1", sceneIndex: 0 },
                             { sceneName: "Scene 2", sceneIndex: 1 }]
                })
            } else if (requestType === "GetVideoSettings") {
                sendRequestResponse(requestId, true, { baseWidth: 1920, baseHeight: 1080 })
            } else if (requestType === "GetInputList") {
                let inputs = []
                for (let i = 0; i < testCase.inputCount; ++i)
                    inputs.push({ inputName: "Input " + (i + 1), inputKind: "pulse_input_capture" })
                sendRequestResponse(requestId, true, { inputs: inputs })
            } else if (requestType === "GetSceneItemList") {
                let items = []
                for (let i = 0; i < 4; ++i) {
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
            width: 900
            height: 820
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
            return audio !== null && audio.count === testCase.inputCount
        })
    }

    function cleanupTestCase() {
        if (window !== null)
            window.destroy()
    }

    // From the narrowest window to maximised, waiting for layout after each step.
    function sweep(check) {
        const sources = findChild(window, "sourcesPanel")
        const audio = findChild(window, "audioPanel")
        const scroll = findChild(window, "panelScroll")
        const was = window.width

        for (let w = 400; w <= 1400; w += 20) {
            window.width = w
            const viewport = w - 2 * Theme.paddingLarge
            tryVerify(function() { return scroll.width === viewport })
            wait(0)
            check(sources, audio, w)
        }

        window.width = was
    }

    function test_they_share_a_row_at_every_width() {
        sweep(function(sources, audio, w) {
            fuzzyCompare(sources.mapToItem(null, 0, 0).y, audio.mapToItem(null, 0, 0).y, 1,
                         "at " + w + " they are not on the same row")
            // Same bottom edge.
            fuzzyCompare(sources.height, audio.height, 1)
        })
    }

    function test_the_mixer_is_never_given_more_than_its_channels() {
        sweep(function(sources, audio, w) {
            verify(audio.width <= audio.naturalWidth + 1,
                   "at " + w + " the mixer got " + audio.width
                   + " for channels worth " + audio.naturalWidth)
        })
    }

    // The list always keeps 280px, or half the row if that's less.
    function test_the_list_is_never_starved_to_feed_the_mixer() {
        sweep(function(sources, audio, w) {
            const pair = sources.width + audio.width
            const owed = Math.min(280, Math.floor(pair / 2))
            verify(sources.width >= owed - 1,
                   "at " + w + " the list was left with " + sources.width
                   + " of " + pair + ", owed " + owed)
        })
    }

    // The list takes whatever the mixer doesn't.
    function test_the_list_takes_the_rest_of_the_row() {
        const row = findChild(window, "sourcesPanel").parent
        sweep(function(sources, audio, w) {
            fuzzyCompare(sources.width + audio.width + row.spacing, row.width, 1,
                         "at " + w + " the row of " + row.width + " is not accounted for")
        })
    }
}
