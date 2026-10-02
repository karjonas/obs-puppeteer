// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import OBSPuppeteer
import ObsPuppeteerTest

// One scroll bar for the whole window, not one per panel. Uses the real Main
// window, since the rule lives in how it sizes its column.
TestCase {
    id: testCase
    name: "WindowScroll"
    when: windowShown

    // More than a short window can show, so there's something to scroll.
    readonly property int sceneCount: 10
    readonly property int inputCount: 9
    readonly property int sourceCount: 14

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
            width: 520
            // Too short for four panels at full size.
            height: 560
            cliHost: "127.0.0.1"
            cliPort: mockServer.port
        }
    }

    property var window: null

    function initTestCase() {
        verify(mockServer.start())
        window = windowComponent.createObject(null)
        verify(window !== null)
        // The window connects from cliHost/cliPort; the panels exist only once
        // authenticated.
        tryVerify(function() {
            const audio = findChild(window, "audioList")
            const sources = findChild(window, "sourceList")
            return audio !== null && sources !== null
                && audio.count === testCase.inputCount
                && sources.count === testCase.sourceCount
        })
        tryVerify(function() { return findChild(window, "panelScroll") !== null })
    }

    function cleanupTestCase() {
        if (window !== null)
            window.destroy()
    }

    function test_the_window_scrolls_its_panels_as_one() {
        const scroll = findChild(window, "panelScroll")

        // It doesn't all fit, so the scroll bar must be showing.
        tryVerify(function() { return scroll.contentHeight > scroll.height })
        tryVerify(function() { return scroll.ScrollBar.vertical.size < 1 })
        compare(scroll.ScrollBar.vertical.policy, ScrollBar.AlwaysOn)
        verify(scroll.ScrollBar.vertical.visible)
    }

    function test_no_panel_scrolls_vertically_on_its_own_data() {
        return [
            { tag: "audio", list: "audioList" },
            { tag: "sources", list: "sourceList" },
        ]
    }

    function test_no_panel_scrolls_vertically_on_its_own(data) {
        const list = findChild(window, data.list)
        verify(list !== null)

        // No scroll bar of its own, and nothing hidden.
        verify(list.ScrollBar.vertical === null)
        tryVerify(function() { return list.contentHeight <= list.height + 1 })
    }

    function test_the_sources_list_takes_no_gestures_at_all() {
        const list = findChild(window, "sourceList")
        // Not interactive, so it doesn't swallow the window's scrolling.
        verify(!list.interactive)
    }

    // The mixer is the only panel that scrolls, and only sideways.
    function test_the_mixer_scrolls_sideways_and_only_sideways() {
        const list = findChild(window, "audioList")
        compare(list.orientation, ListView.Horizontal)
        verify(list.ScrollBar.horizontal !== null)
        verify(list.ScrollBar.vertical === null)

        // Nine inputs don't fit across 520px.
        tryVerify(function() { return list.contentWidth > list.width })
        tryVerify(function() { return list.ScrollBar.horizontal.size < 1 })
    }

    function test_the_scene_grid_is_not_a_scroller_either() {
        const grid = findChild(window, "sceneGrid")
        verify(grid !== null)
        // A plain Item, with nothing to scroll.
        verify(grid.contentHeight === undefined)
    }

    // The controls stay put while the panels scroll.
    function test_the_stream_button_stays_put_while_the_panels_scroll() {
        const scroll = findChild(window, "panelScroll")
        const button = findChild(window, "streamButton")
        verify(button !== null)

        const before = button.mapToItem(null, 0, 0).y
        verify(before + button.height <= window.height + 1)

        scroll.contentY = scroll.contentHeight - scroll.height
        tryVerify(function() { return scroll.contentY > 0 })

        compare(button.mapToItem(null, 0, 0).y, before)
        verify(before + button.height <= window.height + 1)
    }
}
