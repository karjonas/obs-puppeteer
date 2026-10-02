// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// Each panel asks for exactly the height its content needs; the window scrolls
// the column, so anything not asked for is clipped. The sources list needs a
// row per source; the mixer one channel's height regardless of input count.
TestCase {
    id: testCase
    name: "PanelSizing"
    width: 460
    height: 640
    visible: true
    when: windowShown

    readonly property int inputCount: 9
    readonly property int sourceCount: 14

    MockObsServerQml {
        id: mockServer

        onRequestReceived: (requestType, requestId, requestData) => {
            if (requestType === "GetInputList") {
                let inputs = []
                for (let i = 0; i < testCase.inputCount; ++i) {
                    inputs.push({
                        inputName: "Audio Input " + (i + 1),
                        inputKind: "pulse_input_capture"
                    })
                }
                sendRequestResponse(requestId, true, { inputs: inputs })
            } else if (requestType === "GetSceneList") {
                sendRequestResponse(requestId, true, {
                    currentProgramSceneName: "Scene A",
                    scenes: [{ sceneName: "Scene A", sceneIndex: 0 }]
                })
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

    ObsClient {
        id: obs
    }

    AudioPanel {
        id: audio
        width: 460
        height: audio.implicitHeight
        obs: obs
    }

    SourcesPanel {
        id: sources
        width: 460
        height: sources.implicitHeight
        obs: obs
    }

    function initTestCase() {
        verify(mockServer.start())
        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.connectionState === ObsClient.Authenticated })
        tryVerify(function() { return obs.inputs.length === testCase.inputCount })
        tryVerify(function() { return obs.sources.length === testCase.sourceCount })
    }

    function test_the_sources_panel_asks_for_every_row_it_holds() {
        // Fourteen sources.
        compare(sources.visibleRows, sourceCount)
        compare(sources.implicitHeight,
                sources.chromeHeight + sources.heightForRows(sourceCount))
    }

    function test_nothing_is_left_below_the_fold() {
        const list = findChild(sources, "sourceList")
        verify(list !== null)

        // Every row is visible at the requested height.
        tryVerify(function() { return list.contentHeight <= list.height + 1 })
        compare(list.count, sourceCount)
        verify(list.ScrollBar.vertical === null)
    }

    // The mixer's height is one channel's, whatever the input count. See
    // tst_AudioMixer.
    function test_the_mixer_is_the_same_height_whatever_it_holds() {
        compare(audio.implicitHeight, audio.chromeHeight + audio.channelHeight)
        const list = findChild(audio, "audioList")
        compare(list.count, inputCount)
    }

    // The mixer's natural width is counted (a ListView has no implicit width),
    // and the window uses it to split the row.
    function test_the_mixer_asks_for_the_width_its_channels_need() {
        const list = findChild(audio, "audioList")
        compare(audio.naturalWidth,
                inputCount * audio.channelWidth + (inputCount - 1) * list.spacing
                + audio.chromeWidth)

        // At that width nothing is scrolled out of view.
        const was = audio.width
        audio.width = audio.naturalWidth
        tryVerify(function() { return list.contentWidth <= list.width + 1 })
        audio.width = was
    }
}
