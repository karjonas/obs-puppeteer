// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

TestCase {
    id: testCase
    name: "ScenesPanelClickRouting"
    width: 400
    height: 300
    visible: true
    when: windowShown

    property string lastRequestType: ""
    property var lastRequestData: ({})

    MockObsServerQml {
        id: mockServer

        onRequestReceived: (requestType, requestId, requestData) => {
            if (requestType === "GetSceneList") {
                sendRequestResponse(requestId, true, {
                    currentProgramSceneName: "Scene A",
                    scenes: [{ sceneName: "Scene A", sceneIndex: 0 }]
                })
            } else {
                sendRequestResponse(requestId, true, {})
            }

            // Only track the two requests under test; polling responses also arrive here.
            if (requestType === "SetCurrentProgramScene" || requestType === "SetCurrentPreviewScene") {
                testCase.lastRequestType = requestType
                testCase.lastRequestData = requestData
            }
        }
    }

    ObsClient {
        id: obs
    }

    ScenesPanel {
        id: panel
        width: 400
        height: 200
        obs: obs
    }

    function init() {
        lastRequestType = ""
        lastRequestData = {}
    }

    // Clicking a scene sets the preview in Studio Mode and the program otherwise.
    function test_click_behavior_depends_on_studio_mode() {
        verify(mockServer.start())
        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.connectionState === ObsClient.Authenticated })
        tryVerify(function() { return obs.scenes.length === 1 })

        const card = findChild(panel, "sceneCard_Scene A")
        verify(card !== null)

        // Studio Mode off: clicking cuts to program.
        mouseClick(card)
        tryVerify(function() { return lastRequestType === "SetCurrentProgramScene" })
        compare(lastRequestData.sceneName, "Scene A")

        // Studio Mode on: clicking sets the preview. Wait for the initial "off"
        // answer first, or it could undo the event.
        tryVerify(function() { return mockServer.answeredCount("GetStudioModeEnabled") === 1 })
        mockServer.sendEvent("StudioModeStateChanged", { studioModeEnabled: true })
        tryVerify(function() { return obs.studioModeEnabled === true })

        lastRequestType = ""
        mouseClick(card)
        tryVerify(function() { return lastRequestType === "SetCurrentPreviewScene" })
        compare(lastRequestData.sceneName, "Scene A")
    }
}
