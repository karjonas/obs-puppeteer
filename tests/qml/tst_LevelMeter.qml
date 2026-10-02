// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import OBSPuppeteer

// A level lights the right amount of each zone, with the boundaries fixed.
TestCase {
    id: testCase
    name: "LevelMeterZones"
    // Shown, since unshown items report themselves invisible.
    visible: true
    when: windowShown

    Component {
        id: meterComponent

        LevelMeter {
            width: 600
            height: 3
        }
    }

    // The lit zones' length along the bar, found by name.
    function zoneWidths(meter) {
        function extent(objectName) {
            const zone = findChild(meter, objectName)
            verify(zone !== null, "no zone named " + objectName)
            return meter.vertical ? zone.height : zone.width
        }
        return {
            nominal: extent("litNominal"),
            warning: extent("litWarning"),
            error: extent("litError"),
        }
    }

    // The bar's length along its axis.
    function extentOf(meter) {
        return meter.vertical ? meter.height : meter.width
    }

    function test_silence_lights_nothing() {
        const meter = createTemporaryObject(meterComponent, testCase, { peak: 0 })
        const w = zoneWidths(meter)
        compare(w.nominal, 0)
        compare(w.warning, 0)
        compare(w.error, 0)
    }

    function test_quiet_fills_only_the_green_zone() {
        // Half way is -30 dB, inside the nominal zone.
        const meter = createTemporaryObject(meterComponent, testCase, { peak: 0.5 })
        const w = zoneWidths(meter)
        compare(w.nominal, 300)
        compare(w.warning, 0)
        compare(w.error, 0)
    }

    function test_loud_fills_green_fully_and_yellow_partly() {
        // 0.75 is past -20 dB (0.667) but short of -9 dB (0.85).
        const meter = createTemporaryObject(meterComponent, testCase, { peak: 0.75 })
        const w = zoneWidths(meter)
        // Green is full and ends where the track's green does.
        compare(w.nominal, meter.width * meter.warningAt)
        verify(w.warning > 0)
        verify(w.warning < meter.width * (meter.errorAt - meter.warningAt))
        compare(w.error, 0)
    }

    function test_clipping_fills_every_zone() {
        const meter = createTemporaryObject(meterComponent, testCase, { peak: 1.0 })
        const w = zoneWidths(meter)
        compare(w.nominal + w.warning + w.error, meter.width)
    }

    function test_level_is_clamped() {
        // A peak above 1 doesn't paint past the end.
        const meter = createTemporaryObject(meterComponent, testCase, { peak: 4.2 })
        const w = zoneWidths(meter)
        compare(w.nominal + w.warning + w.error, meter.width)
    }

    // Vertical bars fill from the bottom.
    Component {
        id: verticalMeterComponent

        LevelMeter {
            width: 6
            height: 600
            orientation: Qt.Vertical
        }
    }

    function test_a_vertical_bar_lights_the_same_amount() {
        const meter = createTemporaryObject(verticalMeterComponent, testCase, { peak: 0.5 })
        verify(meter.vertical)
        const w = zoneWidths(meter)
        compare(w.nominal, 300)
        compare(w.warning, 0)
        compare(w.error, 0)
    }

    function test_a_vertical_bar_fills_from_the_bottom() {
        const meter = createTemporaryObject(verticalMeterComponent, testCase, { peak: 0.5 })
        const lit = findChild(meter, "litNominal")

        // Half lit, from the bottom edge up.
        compare(lit.y + lit.height, meter.height)
        compare(lit.y, meter.height / 2)
    }

    function test_a_vertical_bar_clips_at_the_top() {
        const meter = createTemporaryObject(verticalMeterComponent, testCase, { peak: 4.2 })
        const w = zoneWidths(meter)
        compare(w.nominal + w.warning + w.error, meter.height)
        compare(findChild(meter, "litError").y, 0)
    }

    // The magnitude is a notch inside the lit bar, not a second fill.
    function test_the_magnitude_is_a_notch_not_a_fill() {
        const meter = createTemporaryObject(verticalMeterComponent, testCase,
                                            { peak: 0.9, magnitude: 0.5 })
        const marker = findChild(meter, "magnitudeMarker")
        verify(marker !== null)
        verify(marker.visible)

        // Its own thickness, wherever it sits.
        compare(marker.height, meter.markerThickness)

        // On the loud side of the level, as OBS draws it vertically.
        compare(marker.y + marker.height, meter.height * 0.5)
    }

    function test_the_magnitude_notch_is_hidden_at_the_bottom_of_the_scale() {
        // Hidden near silence, as in OBS.
        const meter = createTemporaryObject(verticalMeterComponent, testCase,
                                            { peak: 0, magnitude: 0 })
        verify(!findChild(meter, "magnitudeMarker").visible)
    }

    function test_the_magnitude_notch_is_clamped_like_the_bar() {
        const full = createTemporaryObject(verticalMeterComponent, testCase,
                                           { peak: 1.0, magnitude: 1.0 })
        const over = createTemporaryObject(verticalMeterComponent, testCase,
                                           { peak: 1.0, magnitude: 4.2 })

        // Clamped to the top of the scale.
        compare(findChild(over, "magnitudeMarker").y,
                findChild(full, "magnitudeMarker").y)
    }
}
