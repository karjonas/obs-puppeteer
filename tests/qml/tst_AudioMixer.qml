// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// The mixer is laid out like OBS's vertical mixer: fixed height whatever the
// number of inputs, and each meter's ruler agreeing with it.
TestCase {
    id: testCase
    name: "AudioMixer"
    // Wide enough that all nine channels are instantiated; a horizontal ListView
    // only builds delegates near the viewport. The overflow case is in
    // tst_WindowScroll.
    width: 980
    height: 320
    visible: true
    when: windowShown

    readonly property int inputCount: 9

    MockObsServerQml {
        id: mockServer

        onRequestReceived: (requestType, requestId, requestData) => {
            if (requestType === "GetInputList") {
                let inputs = []
                for (let i = 0; i < testCase.inputCount; ++i)
                    inputs.push({ inputName: "Input " + (i + 1), inputKind: "pulse_input_capture" })
                sendRequestResponse(requestId, true, { inputs: inputs })
            } else {
                sendRequestResponse(requestId, true, {})
            }
        }
    }

    ObsClient {
        id: obs
    }

    AudioPanel {
        id: panel
        width: 980
        height: panel.implicitHeight
        obs: obs
    }

    function initTestCase() {
        verify(mockServer.start())
        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.connectionState === ObsClient.Authenticated })
        tryVerify(function() { return obs.inputs.length === testCase.inputCount })
        tryVerify(function() { return findChild(panel, "meter_Input 9_0") !== null })
    }

    // Nine inputs: one channel tall, not nine rows.
    function test_the_panel_is_one_channel_tall_whatever_it_holds() {
        compare(panel.implicitHeight, panel.chromeHeight + panel.channelHeight)
        verify(panel.implicitHeight < 2 * panel.channelHeight,
               "nine inputs should not cost more than one channel of height")
    }

    function test_every_input_gets_a_fader_a_meter_and_a_ruler() {
        for (let i = 1; i <= inputCount; ++i) {
            const name = "Input " + i
            verify(findChild(panel, "fader_" + name) !== null, "no fader for " + name)
            verify(findChild(panel, "meters_" + name) !== null, "no meters for " + name)
            verify(findChild(panel, "meter_" + name + "_0") !== null, "no bar for " + name)
            verify(findChild(panel, "scale_" + name) !== null, "no ruler for " + name)
        }
    }

    function test_the_meters_are_vertical_and_the_ruler_matches_them() {
        const meter = findChild(panel, "meter_Input 1_0")
        const scale = findChild(panel, "scale_Input 1")

        compare(meter.orientation, Qt.Vertical)

        // Same height, so ticks line up with levels.
        tryVerify(function() { return meter.height > 0 && meter.height === scale.height })
        compare(scale.floorDb, -60)
        compare(scale.stepDb, 6)
    }

    function sendLevels(peak) {
        let inputs = []
        for (let i = 0; i < inputCount; ++i) {
            inputs.push({
                inputName: "Input " + (i + 1),
                inputLevelsMul: [[peak / 2, peak, peak], [peak / 4, peak / 2, peak / 2]]
            })
        }
        mockServer.sendEvent("InputVolumeMeters", { inputs: inputs })
    }

    // Level updates (~20/s) must update the bars, not rebuild them.
    function test_a_level_update_moves_the_bars_rather_than_rebuilding_them() {
        // Establish the channel count first; that change may rebuild.
        sendLevels(0.2)
        tryVerify(function() { return findChild(panel, "meter_Input 1_1") !== null })

        const before = findChild(panel, "meter_Input 1_0")
        verify(before !== null)

        for (let i = 0; i < 6; ++i) {
            sendLevels(0.2 + i * 0.05)
            wait(20)
        }

        const after = findChild(panel, "meter_Input 1_0")
        verify(after !== null, "the bar was destroyed by a level update")
        compare(after, before)
    }

    function test_the_bars_still_follow_the_levels() {
        const left = findChild(panel, "meter_Input 1_0")
        const right = findChild(panel, "meter_Input 1_1")

        sendLevels(1.0)
        // Left at the top, right at half the multiplier (well down the dB scale).
        tryVerify(function() { return left.peak > right.peak && right.peak > 0 })
    }

    // OBS's minimum vertical meter height; below it the labels overlap.
    function test_the_meter_is_tall_enough_for_its_ruler() {
        const scale = findChild(panel, "scale_Input 1")
        verify(scale.height >= scale.minimumUsefulHeight,
               "ruler is " + scale.height + ", needs " + scale.minimumUsefulHeight)
        compare(scale.labelCount, 11)
    }
}
