// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

// Bound, so the two Layer instances resolve `root` at compile time.
pragma ComponentBehavior: Bound

import QtQuick

// A scene thumbnail with two layers: changing an on-screen Image's source
// blanks it until the new image decodes, so the next one decodes off screen
// and the layers swap when it's ready.
Item {
    id: root

    property string source: ""
    property int fillMode: Image.PreserveAspectCrop

    readonly property Image _visible: _showB ? _b : _a
    readonly property Image _incoming: _showB ? _a : _b

    property bool _showB: false
    property bool _busy: false
    property string _pending: ""

    onSourceChanged: {
        if (source === "" || source === _pending
                || source === String(_visible.source) || source === String(_incoming.source))
            return
        _pending = source
        if (!_busy)
            _start()
    }

    function _start() {
        _busy = true
        const next = _pending
        _pending = ""
        _incoming.source = next
    }

    function _onIncomingReady(ok) {
        if (ok)
            _swap()
        else
            _incoming.source = ""

        _busy = false
        if (_pending !== "")
            _start()
    }

    function _swap() {
        const outgoing = _visible
        _showB = !_showB
        // The old layer becomes the next decode target.
        outgoing.source = ""
    }

    component Layer: Image {
        id: layer
        anchors.fill: parent
        fillMode: root.fillMode
        visible: layer === root._visible
        // Off the GUI thread, so decoding doesn't stall the window.
        asynchronous: true
        // Each URL is used once, so caching would only grow the cache.
        cache: false
        // Bilinear only: thumbnails arrive at about the drawn size, so mipmaps aren't
        // worth building.
        mipmap: false
        smooth: true

        onStatusChanged: {
            if (layer !== root._incoming || status === Image.Loading || String(layer.source) === "")
                return
            root._onIncomingReady(status === Image.Ready)
        }
    }

    Layer { id: _a }
    Layer { id: _b }
}
