/*
    iris — the prompt of last resort.

    Loaded only when LockScreenUi.qml will not load at all. It imports nothing
    but QtQuick: no Plasma modules, no Kirigami, no shared components from this
    theme, nothing that a system upgrade can take away. If this file cannot
    run, neither can Qt.

    It is deliberately plain. Its whole job is to let you back into your
    session without a TTY.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

Item {
    id: fallback

    /* ScanStatus.qml is not imported here on purpose — this file depends on
       nothing that an upgrade can remove — but the one rule it still keeps is
       that the screen never says "face". A regex costs no dependency. */
    function eyeWords(s) {
        return String(s)
            .replace(/facial recognition/gi, "iris scan")
            .replace(/facial/gi, "iris")
            .replace(/\bface\b/gi, "eye")
            .replace(/\bFace\b/g, "Eye");
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    Column {
        anchors.centerIn: parent
        spacing: 18

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: typeof kscreenlocker_userName !== "undefined" ? kscreenlocker_userName : ""
            color: "#bbbbbb"
            font.pointSize: 12
        }

        Rectangle {
            width: 320
            height: 40
            color: "transparent"
            border.width: 1
            border.color: input.activeFocus ? "#ffffff" : "#555555"

            TextInput {
                id: input

                anchors.fill: parent
                anchors.margins: 10
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                color: "#ffffff"
                font.pointSize: 12
                focus: true

                onAccepted: {
                    authenticator.respond(text);
                    text = "";
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.notification
            color: "#999999"
            font.pointSize: 9
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "iris fallback prompt"
            color: "#444444"
            font.pointSize: 8
        }
    }

    Connections {
        target: authenticator

        function onSucceeded() {
            Qt.quit();
        }

        function onFailed(kind) {
            if (kind === 0) {
                root.notification = "Authentication failed";
                input.text = "";
                input.forceActiveFocus();
            }
        }

        function onInfoMessageChanged() {
            root.notification = fallback.eyeWords(authenticator.infoMessage);
        }

        function onErrorMessageChanged() {
            root.notification = fallback.eyeWords(authenticator.errorMessage);
        }
    }

    Component.onCompleted: {
        input.forceActiveFocus();
        authenticator.startAuthenticating();
    }
}
