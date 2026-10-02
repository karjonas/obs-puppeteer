// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import OBSPuppeteer

// The fader readout follows OBS: below -96 dB it shows "-inf dB".
TestCase {
    id: testCase
    name: "AudioPanelVolumeText"
    when: windowShown

    // Not named `obs`: inside AudioPanel that would resolve to its own property
    // and make a binding loop.
    ObsClient {
        id: client
    }

    Component {
        id: panelComponent

        AudioPanel {
            obs: client
        }
    }

    function test_format_data() {
        return [
            { tag: "unity", db: 0, expected: "0.0 dB" },
            { tag: "one decimal place", db: -13.04, expected: "-13.0 dB" },
            { tag: "rounds", db: -11.25, expected: "-11.3 dB" },
            { tag: "bottom of the fader", db: -60, expected: "-60.0 dB" },
            // OBS's boundary is `db < -96`, so -96 itself still prints.
            { tag: "at the floor", db: -96, expected: "-96.0 dB" },
            { tag: "below the floor", db: -96.1, expected: "-inf dB" },
            { tag: "silent", db: -100, expected: "-inf dB" },
        ]
    }

    function test_format(data) {
        // Per case: createTemporaryObject destroys it after each test function.
        const panel = createTemporaryObject(panelComponent, testCase)
        verify(panel)
        compare(panel.formatVolumeDb(data.db), data.expected)
    }
}
