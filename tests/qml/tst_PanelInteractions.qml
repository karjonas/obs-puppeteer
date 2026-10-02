// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// The source and audio controls send the right request for their current
// state; in particular a visibility toggle requests the opposite of its state.
TestCase {
    id: testCase
    name: "PanelInteractions"
    width: 480
    height: 420
    visible: true
    when: windowShown

    property string lastRequest: ""
    property var lastData: ({})

    MockObsServerQml {
        id: mockServer

        onRequestReceived: (requestType, requestId, requestData) => {
            if (requestType === "GetSceneList") {
                sendRequestResponse(requestId, true, {
                    currentProgramSceneName: "Scene A",
                    scenes: [{ sceneName: "Scene A", sceneIndex: 0 }]
                })
            } else if (requestType === "GetSceneItemList") {
                sendRequestResponse(requestId, true, {
                    sceneItems: [
                        { sourceName: "Visible Source", sceneItemId: 1,
                          inputKind: "browser_source", sceneItemEnabled: true },
                        { sourceName: "Hidden Source", sceneItemId: 2,
                          inputKind: "browser_source", sceneItemEnabled: false }
                    ]
                })
            } else if (requestType === "GetInputList") {
                sendRequestResponse(requestId, true, {
                    inputs: [{ inputName: "Desktop Audio", inputKind: "pulse_output_capture" }]
                })
            } else {
                sendRequestResponse(requestId, true, {})
            }

            // Only record the controls under test; polling also arrives here.
            if (requestType === "SetSceneItemEnabled" || requestType === "ToggleInputMute") {
                testCase.lastRequest = requestType
                testCase.lastData = requestData
            }
        }
    }

    ObsClient {
        id: obs
    }

    // Side by side, so neither covers the other's clicks.
    SourcesPanel {
        id: sources
        y: 0
        width: 480
        height: 190
        obs: obs
    }

    AudioPanel {
        id: audio
        y: 200
        width: 480
        height: 190
        obs: obs
    }

    function initTestCase() {
        verify(mockServer.start())
        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.connectionState === ObsClient.Authenticated })
        tryVerify(function() { return obs.sources.length === 2 })
        tryVerify(function() { return obs.inputs.length === 1 })
    }

    function init() {
        testCase.lastRequest = ""
        testCase.lastData = {}
    }

    function test_hiding_a_visible_source_asks_for_it_to_be_hidden() {
        // Found by name, since views reorder delegates.
        const toggle = findChild(sources, "visibilityToggle_Visible Source")
        verify(toggle !== null)
        mouseClick(toggle)

        tryVerify(function() { return testCase.lastRequest === "SetSceneItemEnabled" })
        compare(testCase.lastData.sceneItemId, 1)
        compare(testCase.lastData.sceneItemEnabled, false)
        compare(testCase.lastData.sceneName, "Scene A")
    }

    function test_showing_a_hidden_source_asks_for_it_to_be_shown() {
        const toggle = findChild(sources, "visibilityToggle_Hidden Source")
        verify(toggle !== null)
        mouseClick(toggle)

        tryVerify(function() { return testCase.lastRequest === "SetSceneItemEnabled" })
        compare(testCase.lastData.sceneItemId, 2)
        compare(testCase.lastData.sceneItemEnabled, true)
    }

    function test_the_mute_button_toggles_that_input() {
        const muteButton = findChild(audio, "muteButton_Desktop Audio")
        verify(muteButton !== null)
        mouseClick(muteButton)

        tryVerify(function() { return testCase.lastRequest === "ToggleInputMute" })
        compare(testCase.lastData.inputName, "Desktop Audio")
    }
}
