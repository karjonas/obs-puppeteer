// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import OBSPuppeteer

// Each icon actually decodes. SVG needs Qt's svg plugin (hence linking
// Qt6::Svg); without it icons silently draw nothing.
TestCase {
    id: testCase
    name: "IconsDecode"
    when: windowShown

    Component {
        id: imageComponent

        Image {
            // Synchronous: only the result matters here.
            asynchronous: false
        }
    }

    function test_icon_decodes_data() {
        return [
            { tag: "audio", source: Icons.audio },
            { tag: "mute", source: Icons.mute },
            { tag: "visible", source: Icons.visible },
            { tag: "invisible", source: Icons.invisible },
            { tag: "app", source: Icons.app },
        ]
    }

    function test_icon_decodes(data) {
        verify(String(data.source).length > 0, "Icons singleton gave an empty url")

        const image = createTemporaryObject(imageComponent, testCase, { source: data.source })
        verify(image)

        tryCompare(image, "status", Image.Ready)
        // Ready alone doesn't prove there's a picture.
        verify(image.sourceSize.width > 0 && image.sourceSize.height > 0,
               "decoded to an empty image")
    }
}
