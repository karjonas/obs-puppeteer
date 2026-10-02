// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

// Bound, so the tick delegates resolve `root` at compile time.
pragma ComponentBehavior: Bound

import QtQuick
import OBSPuppeteer

// The dB ruler beside a vertical meter: a tick and label every 6 dB. Follows
// the rules in OBS's VolumeMeter::paintVTicks and sizeHint. Linear over the
// same range as LevelMeter, so at the same height the ticks line up with it.
Item {
    id: root

    // Same floor as ObsClient's kMeterFloorDb.
    readonly property real floorDb: -60
    readonly property int stepDb: 6
    readonly property int tickLength: 2

    readonly property int labelCount: Math.floor(-floorDb / stepDb) + 1

    // Below this the labels overlap.
    readonly property real minimumUsefulHeight: labelCount * token.implicitHeight * 0.8

    readonly property int textOffset: 8
    implicitWidth: textOffset + token.implicitWidth

    // OBS sizes the ruler for "-88", an over-estimate so it never reflows.
    // Never drawn.
    Text {
        id: token
        visible: false
        text: "-88"
        font.pixelSize: Theme.fontXSmall
    }

    Repeater {
        model: root.labelCount

        delegate: Item {
            id: tick
            required property int index

            readonly property real db: -root.stepDb * index
            readonly property real fromTop: root.height * (db / root.floorDb)

            x: 0
            // Centred on the tick, except 0 dB, which sits below it to stay in bounds,
            // as in OBS.
            y: index === 0 ? Math.round(fromTop)
                           : Math.round(fromTop - height / 2)
            width: root.width
            height: token.implicitHeight

            Rectangle {
                anchors.left: parent.left
                // On the item's top edge at 0 dB, its middle elsewhere.
                y: tick.index === 0 ? 0 : Math.round(parent.height / 2)
                width: root.tickLength
                height: 1
                color: Theme.textMuted
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: root.textOffset
                anchors.verticalCenter: parent.verticalCenter
                text: String(tick.db)
                color: Theme.textMuted
                font.pixelSize: Theme.fontXSmall
            }
        }
    }
}
