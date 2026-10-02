// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

// Bound, so the Prose component resolves `root` at compile time.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import OBSPuppeteer

// Version, platform and licences. Release builds bundle Qt, so the LGPL text
// has to ship with them; it's compiled in. Licences open in place of the
// summary.
Dialog {
    id: root
    objectName: "aboutDialog"

    // Styled like the close-connection dialog; see StatusBar.qml.
    popupType: Popup.Item
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: 360
    // Margins make the popup shrink to fit a short window; the content scrolls.
    margins: Theme.paddingLarge
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    title: qsTr("About OBS Puppeteer")

    // The SPDX identifier of the licence being read, or empty for the summary.
    property string shownLicense: ""

    // What "Copy details" copies.
    readonly property string details:
        "OBS Puppeteer " + Qt.application.version + "\n"
        + "Qt " + AppInfo.qtVersion
        + (AppInfo.qtBuildVersion !== AppInfo.qtVersion ? " (built with " + AppInfo.qtBuildVersion + ")" : "")
        + "\n" + AppInfo.platform

    function showLicense(spdxId) {
        root.shownLicense = spdxId
        scroller.contentY = 0
    }

    onClosed: root.shownLicense = ""

    background: Rectangle {
        color: Theme.bgBase
        border.color: Theme.border
        border.width: 1
        radius: Theme.radius
    }

    header: Label {
        text: root.shownLicense === "" ? root.title : root.shownLicense
        color: Theme.text
        font.pixelSize: 18
        font.bold: true
        elide: Text.ElideRight
        padding: Theme.paddingLarge
        bottomPadding: Theme.padding
        background: null
    }

    footer: DialogButtonBox {
        Material.foreground: Theme.primaryLighter
        background: null

        Button {
            objectName: "aboutSecondaryButton"
            flat: true
            text: root.shownLicense !== "" ? qsTr("Back")
                  : copiedTimer.running ? qsTr("Copied")
                  : qsTr("Copy details")
            DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
            onClicked: {
                if (root.shownLicense !== "") {
                    root.showLicense("")
                } else {
                    AppInfo.copyToClipboard(root.details)
                    copiedTimer.restart()
                }
            }

            Timer {
                id: copiedTimer
                interval: 1500
            }
        }

        Button {
            flat: true
            text: qsTr("Close")
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
    }

    // Text with links: `license:` links open a licence here, others the browser.
    component Prose: Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.text
        linkColor: Theme.primaryLighter
        textFormat: Text.StyledText
        onLinkActivated: function (link) {
            if (link.startsWith("license:"))
                root.showLicense(link.substring("license:".length))
            else
                Qt.openUrlExternally(link)
        }

        HoverHandler {
            cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
    }

    contentItem: Flickable {
        id: scroller
        objectName: "aboutScroller"
        clip: true
        implicitHeight: pages.implicitHeight
        contentWidth: width
        contentHeight: pages.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ObsScrollBar {
            id: scrollBar
        }

        // Only one page is visible, so the dialog fits the shown page. The licence
        // page always scrolls, so it leaves room for the scroll bar.
        ColumnLayout {
            id: pages
            width: scroller.width
                   - (root.shownLicense !== "" ? scrollBar.width + Theme.spacingLarge : 0)
            spacing: 0

            ColumnLayout {
                id: summary
                objectName: "aboutSummary"
                visible: root.shownLicense === ""
                Layout.fillWidth: true
                spacing: Theme.paddingLarge

                Prose {
                    objectName: "aboutVersion"
                    text: qsTr("Version %1").arg(Qt.application.version)
                    font.bold: true
                }

                Prose {
                    text: qsTr("An unofficial control panel for OBS Studio.")
                          + "<br><a href=\"https://github.com/karjonas/obs-puppeteer\">github.com/karjonas/obs-puppeteer</a>"
                }

                Prose {
                    objectName: "aboutLicense"
                    text: qsTr("Copyright © 2026 Jonas Karlsson.<br>Free software under the <a href=\"license:GPL-3.0-or-later\">GNU General Public License, version 3 or later</a>. It comes with ABSOLUTELY NO WARRANTY.")
                }

                Prose {
                    objectName: "aboutQt"
                    text: qsTr("Built with <a href=\"https://www.qt.io/\">Qt</a>, used under the <a href=\"license:LGPL-3.0-or-later\">GNU Lesser General Public License, version 3</a>. Its source is at <a href=\"https://download.qt.io/official_releases/qt/\">download.qt.io</a>, and the third-party components it includes are listed in <a href=\"https://doc.qt.io/qt-6/licenses-used-in-qt.html\">Licenses Used in Qt</a>.")
                }

                Prose {
                    text: qsTr("Icons, colours and metrics from OBS Studio, © OBS Studio contributors, under the GNU General Public License, version 2 or later.")
                }

                Prose {
                    objectName: "aboutDetails"
                    Layout.topMargin: Theme.spacing
                    textFormat: Text.PlainText
                    text: root.details
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSmall
                }
            }

            Prose {
                objectName: "aboutLicenseText"
                visible: root.shownLicense !== ""
                textFormat: Text.PlainText
                text: visible ? AppInfo.licenseText(root.shownLicense) : ""
                font.pixelSize: Theme.fontSmall
            }
        }
    }
}
