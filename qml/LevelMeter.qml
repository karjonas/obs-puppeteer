// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

// Bound, so the Zone instances resolve `root` at compile time.
pragma ComponentBehavior: Bound

import QtQuick
import OBSPuppeteer

// One audio channel's level bar, drawn like OBS's mixer: the track is split
// into green/yellow/red zones at -20 and -9 dB, and the lit part uses the
// brighter shade of each zone. See frontend/components/VolumeMeter.cpp.
//
// OBS's peak-hold marker and clip flash are not reproduced. The dB ruler is
// MeterScale.
Item {
    id: root

    // 0..1 on the -60..0 dB scale.
    property real peak: 0
    // The smoothed level, drawn as a notch like OBS's.
    property real magnitude: 0
    // A grey track tells muted apart from silent.
    property bool muted: false

    // Vertical fills bottom to top, as in OBS's vertical mixer.
    property int orientation: Qt.Horizontal
    readonly property bool vertical: orientation === Qt.Vertical

    // Zone boundaries as fractions of the -60 dB scale.
    readonly property real warningAt: (60 - 20) / 60
    readonly property real errorAt: (60 - 9) / 60

    // Bar thickness, within OBS's 3..6px meterThickness range.
    readonly property int thickness: vertical ? 6 : 3
    implicitWidth: vertical ? thickness : 0
    implicitHeight: vertical ? 0 : thickness

    readonly property int markerThickness: 3

    readonly property real _fill: Math.max(0, Math.min(1, peak))
    readonly property real _magnitude: Math.max(0, Math.min(1, magnitude))

    // Magnitude position in pixels from the quiet end.
    readonly property real magnitudeExtent: (vertical ? height : width) * _magnitude

    // One zone band, positioned along the scale so both orientations share code.
    component Zone: Rectangle {
        required property real from
        required property real to

        readonly property real _from: Math.max(0, Math.min(1, from))
        readonly property real _to: Math.max(_from, Math.min(1, to))

        x: root.vertical ? 0 : root.width * _from
        // Measured from the top; the quiet end of a vertical bar is the bottom.
        y: root.vertical ? root.height * (1 - _to) : 0
        width: root.vertical ? root.width : root.width * (_to - _from)
        height: root.vertical ? root.height * (_to - _from) : root.height
    }

    // The track: all three zones at full length.
    Zone {
        from: 0
        to: root.warningAt
        color: root.muted ? Theme.meterMutedNominal : Theme.meterTrackNominal
    }

    Zone {
        from: root.warningAt
        to: root.errorAt
        color: root.muted ? Theme.meterMutedWarning : Theme.meterTrackWarning
    }

    Zone {
        from: root.errorAt
        to: 1
        color: root.muted ? Theme.meterMutedError : Theme.meterTrackError
    }

    // The lit bar. Each zone is clamped to its span so the boundaries line up
    // with the track.
    Zone {
        objectName: "litNominal"
        from: 0
        to: Math.min(root._fill, root.warningAt)
        color: Theme.meterNominal
    }

    Zone {
        objectName: "litWarning"
        from: root.warningAt
        to: Math.min(root._fill, root.errorAt)
        color: Theme.meterWarning
    }

    Zone {
        objectName: "litError"
        from: root.errorAt
        to: root._fill
        color: Theme.meterError
    }

    // The magnitude notch, hidden near silence, as in OBS.
    Rectangle {
        objectName: "magnitudeMarker"
        visible: root.magnitudeExtent >= root.markerThickness
        color: Theme.meterMagnitude

        // Which side of the level the notch sits on differs by orientation, copied
        // from OBS's fillRect calls.
        x: root.vertical ? 0 : root.magnitudeExtent - root.markerThickness
        y: root.vertical ? root.height - root.magnitudeExtent - root.markerThickness : 0
        width: root.vertical ? root.width : root.markerThickness
        height: root.vertical ? root.markerThickness : root.height
    }
}
