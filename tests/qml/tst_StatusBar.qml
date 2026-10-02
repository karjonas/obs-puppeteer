// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// How the status line phrases its numbers, and which appear. Uses a fake
// obs-websocket so the streaming case can be tested.
TestCase {
    id: testCase
    name: "StatusBarNumbers"
    width: 520
    height: 200
    visible: true
    when: windowShown

    property bool streaming: false
    property int skippedFrames: 0
    // Whether this OBS answers GetStats.
    property bool reportsStats: false

    MockObsServerQml {
        id: mockServer

        onRequestReceived: (requestType, requestId, requestData) => {
            if (requestType === "GetStreamStatus") {
                sendRequestResponse(requestId, true, {
                    outputActive: testCase.streaming,
                    outputTimecode: "01:02:03.000",
                    outputBytes: 0,
                    outputSkippedFrames: testCase.skippedFrames,
                    outputTotalFrames: 1000
                })
            } else if (requestType === "GetRecordDirectory") {
                sendRequestResponse(requestId, true, { recordDirectory: "/home/streamer/Videos" })
            } else if (requestType === "GetStats") {
                if (testCase.reportsStats)
                    sendRequestResponse(requestId, true, { activeFps: 60, cpuUsage: 4.5 })
                else
                    sendRequestResponse(requestId, false, {})
            } else {
                sendRequestResponse(requestId, true, {})
            }
        }
    }

    ObsClient {
        id: obs
    }

    StatusBar {
        id: statusBar
        width: 520
        obs: obs
    }

    function initTestCase() {
        verify(mockServer.start())
    }

    // Kilobits below 1000, megabits above.
    function test_bitrate_reads_in_the_right_unit_data() {
        return [
            { tag: "zero", kbps: 0, expected: "0 kb/s" },
            { tag: "kilobits", kbps: 850, expected: "850 kb/s" },
            { tag: "rounds to whole kilobits", kbps: 850.4, expected: "850 kb/s" },
            { tag: "switches at a megabit", kbps: 1000, expected: "1.0 Mb/s" },
            { tag: "megabits", kbps: 6000, expected: "6.0 Mb/s" },
            { tag: "one decimal", kbps: 6543, expected: "6.5 Mb/s" },
        ]
    }

    function test_bitrate_reads_in_the_right_unit(data) {
        compare(statusBar.formatBitrate(data.kbps), data.expected)
    }

    // Skipped frames are hidden at zero.
    function test_skipped_frames_appear_only_when_there_are_any() {
        const skipped = findChild(statusBar, "skippedLabel")
        verify(skipped !== null)

        testCase.streaming = true
        testCase.skippedFrames = 0
        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.streaming })
        compare(skipped.visible, false)

        testCase.skippedFrames = 5
        tryVerify(function() { return skipped.visible })
        // 5 of 1000 frames: under one percent is a warning, not an error.
        compare(skipped.text, "5 skipped (0.5%)")
        compare(skipped.color, Theme.warning)

        testCase.skippedFrames = 50
        tryVerify(function() { return obs.streamSkippedPercent >= 1.0 })
        compare(skipped.color, Theme.danger)
    }

    // The recording folder is shown directly, not in a tooltip.
    function test_record_directory_is_shown() {
        const label = findChild(statusBar, "recordDirectoryLabel")
        verify(label !== null)

        // Tests share one client, so disconnect it to start fresh.
        obs.disconnectFromObs()
        tryVerify(function() { return !label.visible })

        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return label.visible })
        compare(label.text, "/home/streamer/Videos")
        compare(findChild(statusBar, "recordDirectoryCaption").visible, true)

        // Forgotten with the connection.
        obs.disconnectFromObs()
        tryVerify(function() { return !label.visible })
    }

    function test_bitrate_is_hidden_when_not_streaming() {
        const bitrate = findChild(statusBar, "bitrateLabel")
        verify(bitrate !== null)

        testCase.streaming = false
        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.connectionState === ObsClient.Authenticated })
        tryVerify(function() { return !obs.streaming })
        compare(bitrate.visible, false)
    }
}
