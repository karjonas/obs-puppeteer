// Copyright (C) 2026 Jonas Karlsson
// SPDX-License-Identifier: GPL-3.0-or-later

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import OBSPuppeteer

Item {
    id: root
    required property ObsClient obs

    // The last address that worked, taken from the client so command-line
    // connections are remembered too. The password is never stored.
    Settings {
        id: saved
        category: "connection"

        property string host: "localhost"
        property int port: 4455
        property bool remember: true
        // Previous addresses, most recent first, as "host:port" strings.
        property var recent: []
    }

    // What is stored, exposed for the tests.
    readonly property string rememberedHost: saved.host
    readonly property int rememberedPort: saved.port
    readonly property var rememberedRecent: saved.recent || []

    readonly property int maxRecent: 6

    readonly property var recentConnections: (saved.recent || []).map(function (entry) {
        // Split on the last colon so IPv6 literals work.
        const separator = entry.lastIndexOf(":")
        return {
            host: separator < 0 ? entry : entry.substring(0, separator),
            port: separator < 0 ? 4455 : (parseInt(entry.substring(separator + 1), 10) || 4455)
        }
    })

    function forgetConnections() {
        saved.host = "localhost"
        saved.port = 4455
        saved.recent = []
    }

    // Removes one remembered address. If it's also the stored last address, that
    // goes back to the default too.
    function forgetConnection(host, port) {
        const entry = host + ":" + port
        saved.recent = (saved.recent || []).filter(function (existing) { return existing !== entry })
        if (saved.host === host && saved.port === port) {
            saved.host = "localhost"
            saved.port = 4455
        }
    }

    // Runs `change` without disturbing what the form shows: the fields follow the
    // stored address, but forgetting it shouldn't overwrite what's typed.
    function keepingFields(change) {
        const host = hostField.editText
        const port = portField.text
        change()
        hostField.editText = host
        portField.text = port
    }

    function rememberConnection(host, port) {
        const entry = host + ":" + port
        const kept = (saved.recent || []).filter(function (existing) { return existing !== entry })
        kept.unshift(entry)
        saved.recent = kept.slice(0, root.maxRecent)
    }

    // Marks which remembered addresses are reachable.
    ConnectionProbe {
        id: probe
    }

    function refreshReachability() {
        probe.check(root.recentConnections)
    }

    Component.onCompleted: root.refreshReachability()

    // Re-probe when the form comes back after a disconnect or failed attempt.
    onVisibleChanged: if (visible) root.refreshReachability()

    Connections {
        target: root.obs

        function onConnectionStateChanged() {
            if (root.obs.connectionState !== ObsClient.Authenticated)
                return

            // Unticked, nothing new is saved; what's already saved stays.
            if (saved.remember) {
                saved.host = root.obs.host
                saved.port = root.obs.port
                root.rememberConnection(root.obs.host, root.obs.port)
            }
        }
    }

    function tryConnect() {
        if (connectButton.enabled)
            root.obs.connectToObs(hostField.editText, parseInt(portField.text, 10) || 4455, passwordField.text)
    }

    ColumnLayout {
        id: form
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 340)
        spacing: 16

        // The logo carries its own background in the window colour.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spacingLarge

            Image {
                objectName: "logo"
                source: Icons.app
                sourceSize.width: 56
                sourceSize.height: 56
                Layout.alignment: Qt.AlignVCenter
            }

            Label {
                text: qsTr("OBS Puppeteer")
                font.pixelSize: 24
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // The version, for bug reports, and the way into the About dialog.
        Label {
            objectName: "versionLabel"
            text: qsTr("version %1").arg(Qt.application.version)
                  + " · <a href=\"about\">" + qsTr("About") + "</a>"
            textFormat: Text.StyledText
            color: Theme.textMuted
            linkColor: Theme.primaryLighter
            font.pixelSize: Theme.fontSmall
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Theme.padding
            onLinkActivated: aboutDialog.open()

            HoverHandler {
                cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }

        ObsHostField {
            id: hostField
            objectName: "hostField"
            Layout.fillWidth: true
            model: root.recentConnections
            reachable: probe.reachable

            // A Binding, because the combo box rewrites editText when its model changes.
            Binding on editText {
                value: saved.host
            }

            // Picking a previous address restores its port too.
            onActivated: function (index) {
                portField.text = root.recentConnections[index].port
            }
            onAccepted: root.tryConnect()
            onRemoveRequested: function (index) {
                const entry = root.recentConnections[index]
                root.keepingFields(function () { root.forgetConnection(entry.host, entry.port) })
            }
        }

        TextField {
            id: portField
            objectName: "portField"
            Layout.fillWidth: true
            placeholderText: qsTr("Port")
            text: saved.port
            inputMethodHints: Qt.ImhDigitsOnly
            onAccepted: root.tryConnect()
        }

        TextField {
            id: passwordField
            Layout.fillWidth: true
            placeholderText: qsTr("Password (leave blank if disabled)")
            echoMode: TextInput.Password
            onAccepted: root.tryConnect()
        }

        CheckBox {
            objectName: "rememberCheckBox"
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Remember this address")
            checked: saved.remember
            onToggled: saved.remember = checked
        }

        ObsButton {
            id: connectButton
            Layout.fillWidth: true
            // Automatic retries don't count as connecting: the button stays
            // usable so another address can be tried meanwhile.
            readonly property bool connecting: root.obs.connectionState === ObsClient.Connecting
                                               && !root.obs.reconnecting
            text: connecting ? qsTr("Connecting…") : qsTr("Connect")
            enabled: !connecting && hostField.editText.length > 0
            onClicked: root.tryConnect()
        }
    }

    // Below the form rather than in it, so the error appearing or clearing (as it
    // does on each attempt) doesn't re-centre the form and make it jump.
    Label {
        objectName: "connectionError"
        anchors.top: form.bottom
        anchors.topMargin: 24
        anchors.horizontalCenter: form.horizontalCenter
        width: form.width
        visible: root.obs.lastError.length > 0
        text: root.obs.lastError
        color: Theme.danger
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }

    AboutDialog {
        id: aboutDialog
    }
}
