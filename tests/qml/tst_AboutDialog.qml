// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtTest
import OBSPuppeteer

// The About dialog opens, names the build and Qt, carries the licence texts,
// and scrolls in the shortest window the app allows.
TestCase {
    id: testCase
    name: "AboutDialog"
    width: 400
    // The app's minimumHeight, shorter than the dialog.
    height: 320
    visible: true
    when: windowShown

    ObsClient {
        id: obs
    }

    StatusBar {
        id: statusBar
        width: testCase.width
        obs: obs
    }

    function dialog() {
        const found = findChild(statusBar, "aboutDialog")
        verify(found !== null)
        return found
    }

    function openFromLink() {
        const link = findChild(statusBar, "aboutLink")
        verify(link !== null)
        mouseClick(link)
        tryVerify(function() { return dialog().opened })
    }

    function init() {
        dialog().close()
        tryVerify(function() { return !dialog().visible })
    }

    function test_the_status_bar_link_opens_it() {
        openFromLink()
    }

    function test_it_says_which_qt_this_is() {
        openFromLink()
        const details = findChild(dialog().contentItem, "aboutDetails")
        verify(details !== null)
        verify(details.text.indexOf("Qt " + AppInfo.qtVersion) !== -1)
        verify(details.text.indexOf(AppInfo.platform) !== -1)
    }

    // The GPL for the app, the LGPL for Qt.
    function test_the_licence_texts_are_compiled_in_data() {
        return [
            { tag: "GPL", id: "GPL-3.0-or-later", heading: "GNU GENERAL PUBLIC LICENSE" },
            { tag: "LGPL", id: "LGPL-3.0-or-later", heading: "GNU LESSER GENERAL PUBLIC LICENSE" },
        ]
    }

    function test_the_licence_texts_are_compiled_in(data) {
        verify(AppInfo.licenseText(data.id).startsWith(data.heading))
    }

    function test_an_unknown_licence_is_empty() {
        compare(AppInfo.licenseText("not-a-licence"), "")
    }

    // Opens in place of the summary; Back returns.
    function test_a_licence_opens_in_place_and_back_returns() {
        openFromLink()
        const summary = findChild(dialog().contentItem, "aboutSummary")
        const licence = findChild(dialog().contentItem, "aboutLicenseText")
        verify(summary !== null && licence !== null)

        dialog().showLicense("LGPL-3.0-or-later")
        tryVerify(function() { return licence.visible && !summary.visible })
        verify(licence.text.startsWith("GNU LESSER GENERAL PUBLIC LICENSE"))

        const back = findChild(dialog().footer, "aboutSecondaryButton")
        verify(back !== null)
        compare(back.text, "Back")
        mouseClick(back)
        tryVerify(function() { return summary.visible && !licence.visible })
    }

    // Reopening shows the summary.
    function test_reopening_shows_the_summary() {
        openFromLink()
        dialog().showLicense("GPL-3.0-or-later")
        dialog().close()
        tryVerify(function() { return !dialog().visible })

        openFromLink()
        compare(dialog().shownLicense, "")
    }

    // Fits the window and scrolls.
    function test_it_fits_a_short_window() {
        openFromLink()
        dialog().showLicense("GPL-3.0-or-later")
        tryVerify(function() {
            return dialog().y >= 0 && dialog().y + dialog().height <= testCase.height
        })
        const scroller = dialog().contentItem
        verify(scroller.contentHeight > scroller.height)
    }

    function test_copy_details_says_it_copied() {
        openFromLink()
        const button = findChild(dialog().footer, "aboutSecondaryButton")
        compare(button.text, "Copy details")
        mouseClick(button)
        compare(button.text, "Copied")
        tryCompare(button, "text", "Copy details", 3000)
    }
}
