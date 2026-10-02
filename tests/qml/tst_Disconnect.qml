// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// Closing a connection must stop the automatic reconnect. It asks first:
// cancelling changes nothing, confirming closes for good, even mid-stream.
TestCase {
    id: testCase
    name: "CloseConnection"
    width: 520
    height: 220
    visible: true
    when: windowShown

    property bool live: false

    MockObsServerQml {
        id: mockServer

        onRequestReceived: (requestType, requestId, requestData) => {
            if (requestType === "GetStreamStatus") {
                sendRequestResponse(requestId, true, {
                    outputActive: testCase.live,
                    outputTimecode: "00:10:00.000"
                })
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

    function dialog() {
        const found = findChild(statusBar, "confirmClose")
        verify(found !== null)
        return found
    }

    function closeButton() {
        const button = findChild(statusBar, "closeConnectionButton")
        verify(button !== null)
        return button
    }

    function initTestCase() {
        verify(mockServer.start())
    }

    function init() {
        // A modal dialog left open would swallow the next test's clicks.
        dialog().close()
        testCase.live = false
        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.connectionState === ObsClient.Authenticated })
        tryVerify(function() { return !obs.streaming })
    }

    function test_it_asks_before_closing() {
        mouseClick(closeButton())

        const warning = findChild(statusBar, "closeWarning")
        verify(warning !== null)
        tryVerify(function() { return warning.visible })

        // It names what closes and what doesn't.
        verify(warning.text.indexOf("127.0.0.1") !== -1)
        verify(warning.text.indexOf("keeps running") !== -1)

        // Asking doesn't disconnect.
        compare(obs.connectionState, ObsClient.Authenticated)
    }

    function test_cancelling_leaves_the_connection_alone() {
        mouseClick(closeButton())
        tryVerify(function() { return dialog().visible })

        dialog().reject()
        tryVerify(function() { return !dialog().visible })

        wait(200)
        compare(obs.connectionState, ObsClient.Authenticated)
    }

    function test_confirming_closes() {
        mouseClick(closeButton())
        tryVerify(function() { return dialog().visible })

        dialog().accept()
        tryVerify(function() { return obs.connectionState === ObsClient.Disconnected })
    }

    // Also while streaming.
    function test_it_closes_while_streaming() {
        testCase.live = true
        tryVerify(function() { return obs.streaming })

        mouseClick(closeButton())
        tryVerify(function() { return dialog().visible })
        dialog().accept()

        tryVerify(function() { return obs.connectionState === ObsClient.Disconnected })
    }

    // It stays closed past the 3 s reconnect delay.
    function test_it_stays_closed() {
        mouseClick(closeButton())
        tryVerify(function() { return dialog().visible })
        dialog().accept()
        tryVerify(function() { return obs.connectionState === ObsClient.Disconnected })

        wait(4000)
        compare(obs.connectionState, ObsClient.Disconnected)
    }

    // Connecting again still works.
    function test_connecting_again_still_works() {
        mouseClick(closeButton())
        tryVerify(function() { return dialog().visible })
        dialog().accept()
        tryVerify(function() { return obs.connectionState === ObsClient.Disconnected })

        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.connectionState === ObsClient.Authenticated })
    }
}
