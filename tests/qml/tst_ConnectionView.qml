// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// The form remembers the last address that worked, unless told not to.
TestCase {
    id: testCase
    name: "ConnectionViewRemembersAddress"
    width: 320
    height: 420
    // Shown, since some tests check where presses land.
    visible: true
    when: windowShown

    MockObsServerQml {
        id: mockServer

        onRequestReceived: (requestType, requestId, requestData) => {
            sendRequestResponse(requestId, true, {})
        }
    }

    ObsClient {
        id: obs
    }

    ConnectionView {
        id: view
        anchors.fill: parent
        obs: obs
    }

    // Started once: it can't listen again after stopping.
    function initTestCase() {
        verify(mockServer.start())
    }

    function connectToMock() {
        obs.connectToObs("127.0.0.1", mockServer.port, "")
        tryVerify(function() { return obs.connectionState === ObsClient.Authenticated })
    }

    function hostField() {
        const field = findChild(view, "hostField")
        verify(field !== null)
        return field
    }

    // Settings persist across runs, so reset them first. Emitting toggled writes
    // the setting as a click would.
    function init() {
        const remember = findChild(view, "rememberCheckBox")
        verify(remember !== null)
        remember.checked = true
        remember.toggled()
        obs.disconnectFromObs()
    }

    function test_remembers_the_address_it_connected_to() {
        connectToMock()

        tryVerify(function() { return view.rememberedHost === "127.0.0.1" })
        compare(view.rememberedPort, mockServer.port)

        // ...and offered again next time, port included.
        compare(view.rememberedRecent[0], "127.0.0.1:" + mockServer.port)
        compare(hostField().model[0].host, "127.0.0.1")
        compare(hostField().model[0].port, mockServer.port)
    }

    // The history: most recent first, no duplicates, capped.
    function test_history_is_most_recent_first_without_duplicates() {
        view.forgetConnections()

        view.rememberConnection("studio-pc.local", 4455)
        view.rememberConnection("192.168.1.40", 4455)
        compare(view.rememberedRecent, ["192.168.1.40:4455", "studio-pc.local:4455"])

        // Reconnecting to a known address moves it up.
        view.rememberConnection("studio-pc.local", 4455)
        compare(view.rememberedRecent, ["studio-pc.local:4455", "192.168.1.40:4455"])

        // Same host, different port: a different entry.
        view.rememberConnection("studio-pc.local", 4466)
        compare(view.rememberedRecent.length, 3)
        compare(view.rememberedRecent[0], "studio-pc.local:4466")
    }

    function test_history_stops_at_the_cap() {
        view.forgetConnections()

        for (let i = 0; i < view.maxRecent + 3; ++i)
            view.rememberConnection("host-" + i, 4455)

        compare(view.rememberedRecent.length, view.maxRecent)
        // The oldest entries drop off.
        compare(view.rememberedRecent[0], "host-" + (view.maxRecent + 2) + ":4455")
        verify(view.rememberedRecent.indexOf("host-0:4455") === -1)
    }

    // Two addresses, most recent first: [studio-pc.local:4466, first.local:4455].
    function seedTwoAddresses() {
        view.forgetConnections()
        view.rememberConnection("first.local", 4455)
        view.rememberConnection("studio-pc.local", 4466)

        const host = hostField()
        compare(host.model.length, 2)
        return host
    }

    // Picking a previous address restores its port. Driven by real presses on the
    // box and the row, since the editor covering the control once made the list
    // unreachable by mouse.
    function test_the_list_opens_on_a_press_and_an_entry_fills_the_form() {
        const host = seedTwoAddresses()

        mouseClick(host, host.width - Theme.padding, host.height / 2)
        tryVerify(function() { return host.popup.visible })

        const list = host.popup.contentItem
        tryVerify(function() { return list.itemAtIndex(1) !== null })
        const row = list.itemAtIndex(1)
        mouseClick(row, row.width / 2, row.height / 2)

        tryVerify(function() { return !host.popup.visible })
        compare(host.editText, "first.local")
        compare(findChild(view, "portField").text, "4455")
    }

    // And from the keyboard, since the editor holds focus.
    function test_the_list_can_be_driven_from_the_keyboard() {
        const host = seedTwoAddresses()

        host.contentItem.forceActiveFocus()
        keyClick(Qt.Key_Down)
        tryVerify(function() { return host.popup.visible })

        // Down again moves through the list.
        keyClick(Qt.Key_Down)
        compare(host.highlightedIndex, 1)

        // Return picks the highlighted row, port included.
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !host.popup.visible })
        compare(host.editText, "first.local")
        compare(findChild(view, "portField").text, "4455")
    }

    // Escape leaves the form unchanged.
    function test_escape_closes_the_list_without_choosing() {
        const host = seedTwoAddresses()
        const port = findChild(view, "portField")
        const wasPort = port.text

        host.contentItem.forceActiveFocus()
        keyClick(Qt.Key_Down)
        tryVerify(function() { return host.popup.visible })
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Escape)

        tryVerify(function() { return !host.popup.visible })
        compare(port.text, wasPort)
    }

    // The reachability dot: green only when reachable; hollow when down or unknown.
    function test_reachability_is_three_states() {
        const host = hostField()
        host.reachable = { "up.local:4455": true, "down.local:4455": false }

        compare(host.reachabilityOf({ host: "up.local", port: 4455 }), true)
        compare(host.reachabilityOf({ host: "down.local", port: 4455 }), false)
        compare(host.reachabilityOf({ host: "unknown.local", port: 4455 }), null)
    }

    // Unticking deletes nothing; the saved addresses stay.
    function test_unticking_keeps_saved_addresses() {
        seedTwoAddresses()

        const remember = findChild(view, "rememberCheckBox")
        mouseClick(remember)
        verify(!remember.checked)

        compare(view.rememberedRecent, ["studio-pc.local:4466", "first.local:4455"])
    }

    // Connecting while unticked saves nothing new, and leaves what's saved alone.
    function test_connecting_while_unticked_saves_nothing() {
        seedTwoAddresses()
        const remember = findChild(view, "rememberCheckBox")
        remember.checked = false
        remember.toggled()

        connectToMock()

        compare(view.rememberedHost, "localhost")
        compare(view.rememberedRecent, ["studio-pc.local:4466", "first.local:4455"])
    }

    function openList(host) {
        mouseClick(host, host.width - Theme.padding, host.height / 2)
        tryVerify(function() { return host.popup.visible })
        const list = host.popup.contentItem
        tryVerify(function() { return list.itemAtIndex(1) !== null })
        return list
    }

    // The × forgets that one address; the others stay, and the list stays open.
    function test_the_x_forgets_one_address() {
        const host = seedTwoAddresses()
        host.editText = "typed.local"
        const list = openList(host)

        const forget = findChild(list, "forget_first.local:4455")
        verify(forget !== null)
        mouseClick(forget)

        tryCompare(view, "rememberedRecent", ["studio-pc.local:4466"])
        verify(host.popup.visible)
        compare(host.editText, "typed.local")
    }

    // Forgetting the stored last address resets it too.
    function test_forgetting_the_last_address_resets_it() {
        connectToMock()
        tryVerify(function() { return view.rememberedHost === "127.0.0.1" })
        obs.disconnectFromObs()

        const host = hostField()
        const list = openList(host)
        const forget = findChild(list, "forget_127.0.0.1:" + mockServer.port)
        verify(forget !== null)
        mouseClick(forget)

        tryCompare(view, "rememberedHost", "localhost")
        verify(view.rememberedRecent.indexOf("127.0.0.1:" + mockServer.port) === -1)
    }

    // Shift+Delete forgets the highlighted address; plain Delete doesn't.
    function test_shift_delete_forgets_the_highlighted_address() {
        const host = seedTwoAddresses()
        host.contentItem.forceActiveFocus()
        keyClick(Qt.Key_Down)
        tryVerify(function() { return host.popup.visible })
        keyClick(Qt.Key_Down)
        compare(host.highlightedIndex, 1)

        keyClick(Qt.Key_Delete)
        compare(view.rememberedRecent.length, 2)

        keyClick(Qt.Key_Delete, Qt.ShiftModifier)
        tryCompare(view, "rememberedRecent", ["studio-pc.local:4466"])
    }
}
