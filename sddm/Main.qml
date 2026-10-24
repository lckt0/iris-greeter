pragma ComponentBehavior: Bound

/*
    iris — SDDM greeter.

    Every widget on this screen is drawn by this theme. Nothing is inherited
    from org.kde.breeze.components, and nothing is read from an icon theme or
    a colour scheme, so the greeter does not depend on anything living in a
    home directory it cannot open. The only outside asset is the font, which
    is installed system-wide.

    The eye in the middle is the avatar. It blinks while it waits, scans when
    pam_howdy scans, and reports what PAM said — see ScanStatus.qml for the
    sentence table and IrisScanner.qml for the drawing.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator

Item {
    id: root

    width: 1600
    height: 900
    focus: true

    Tokens { id: tok }
    ScanStatus { id: interpreter }

    /* ---- authentication state ---- */

    /* Set from the moment a secret is handed to PAM until it answers. */
    property bool authenticating: false

    /* True when this attempt was started for the eye rather than typed. */
    property bool eyeAttempt: false

    property string scanPhase: "idle"
    property string statusText: ""

    readonly property string userName: userField.text.length > 0
        ? userField.text
        : (userModel.lastUser ? userModel.lastUser : "")

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    function beginLogin(secret) {
        if (root.authenticating || root.userName.length === 0) {
            return;
        }
        root.eyeAttempt = (secret.length === 0);
        root.authenticating = true;

        if (root.eyeAttempt) {
            /* Say what is about to happen before PAM gets around to printing
               its own notice; pam_howdy can take a moment to open the camera
               and a silent screen reads as a hang. */
            root.scanPhase = "scanning";
            root.statusText = "Looking for your eye";
        } else {
            root.scanPhase = "idle";
            root.statusText = "";
        }

        sddm.login(root.userName, secret, sessionIndex);
    }

    /* Idle reset. Never fires mid-attempt. */
    Timer {
        id: settle
        interval: tok.holdMs
        onTriggered: {
            if (root.authenticating) {
                settle.restart();
            } else {
                root.scanPhase = "idle";
                root.statusText = "";
            }
        }
    }

    onStatusTextChanged: if (statusText.length > 0) settle.restart()

    Connections {
        target: sddm

        /* Everything PAM says on its way through, pam_howdy included. */
        function onInformationMessage(message) {
            const verdict = interpreter.classify(message);
            if (verdict === null) {
                return;
            }
            if (verdict.phase.length > 0) {
                root.scanPhase = verdict.phase;
            }
            root.statusText = verdict.text;
        }

        function onLoginFailed() {
            root.authenticating = false;

            if (root.eyeAttempt) {
                /* If PAM never explained itself the ring is still turning;
                   close it out rather than leaving it to spin. */
                if (root.scanPhase === "scanning") {
                    root.scanPhase = "failed";
                }
                if (root.statusText.length === 0) {
                    root.statusText = "Eye not recognised";
                }
            } else {
                /* A typed password was rejected; don't blame the scanner even
                   if pam_howdy reported something on the way. */
                root.scanPhase = "idle";
                root.statusText = "Wrong password";
            }

            passwordField.clear();
            passwordField.reject();
            passwordField.takeFocus();
            settle.restart();
        }

        function onLoginSucceeded() {
            root.authenticating = false;
            if (root.eyeAttempt && root.scanPhase !== "matched") {
                root.scanPhase = "matched";
            }

            /* No fade-out: the compositor handover that follows is black
               anyway, so the matched eye stays on screen until SDDM exits. */
        }
    }

    /* ---- focus hardening, defence 3 ----
       A keystroke that arrives while the field is not focused is typed into
       it instead of being dropped. This is what stops the greeter from
       handing PAM a truncated secret when the compositor is slow to hand
       over keyboard focus. */
    Keys.onPressed: event => {
        if (root.authenticating) {
            event.accepted = false;
            return;
        }
        if (!passwordField.hasFocus && !userField.activeFocus) {
            passwordField.takeFocus();

            const printable = event.text.length === 1
                && event.text.charCodeAt(0) >= 0x20
                && event.text.charCodeAt(0) !== 0x7f
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));

            if (printable) {
                passwordField.append(event.text);
                event.accepted = true;
                return;
            }
        }
        event.accepted = false;
    }

    /* ---- session and keyboard selection ---- */

    property int sessionIndex: sessionModel.lastIndex

    readonly property string sessionName: {
        const i = sessionModel.index(root.sessionIndex, 0);
        const n = sessionModel.data(i, Qt.UserRole + 4);
        return n ? String(n) : "Session";
    }

    function cycleSession() {
        if (sessionModel.rowCount() < 2) {
            return;
        }
        root.sessionIndex = (root.sessionIndex + 1) % sessionModel.rowCount();
        root.statusText = root.sessionName;
        passwordField.takeFocus();
    }

    function cycleLayout() {
        if (!keyboard || keyboard.layouts.length < 2) {
            return;
        }
        keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length;
        root.statusText = keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase();
        passwordField.takeFocus();
    }

    /* ---- clock ---- */

    property date now: new Date()

    Timer {
        running: true
        repeat: true
        interval: 1000
        onTriggered: root.now = new Date()
    }

    /* ------------------------------------------------------------------ */
    /*  scene                                                              */
    /* ------------------------------------------------------------------ */

    Repeater {
        model: screenModel

        delegate: Backdrop {
            id: screen

            /* ScreenModel exposes exactly one role, "geometry". */
            required property rect geometry

            x: screen.geometry.x
            y: screen.geometry.y
            width: screen.geometry.width
            height: screen.geometry.height
            caption: config.caption
            showCaption: config.showCaption === "true"
        }
    }

    Item {
        id: stage

        anchors.fill: parent

        Behavior on opacity {
            NumberAnimation { duration: tok.veryLong; easing.type: Easing.InOutQuad }
        }

        /* Clock */
        Column {
            id: clock

            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.14)
            spacing: 10
            visible: config.showClock !== "false"

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.now, "HH:mm")
                color: tok.line86
                font.family: tok.mono
                font.weight: Font.ExtraLight
                font.pointSize: 52
                font.letterSpacing: 6
                renderType: Text.NativeRendering
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.now, "dddd, d MMMM").toLowerCase()
                color: tok.line28
                font.family: tok.mono
                font.weight: Font.Light
                font.pointSize: 10
                font.letterSpacing: 4
                renderType: Text.NativeRendering
            }
        }

        /* The eye, the name, the secret, the verdict */
        Column {
            id: core

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Math.round(parent.height * 0.045)
            spacing: 0

            IrisScanner {
                id: eye

                anchors.horizontalCenter: parent.horizontalCenter
                width: 208
                height: 208
                phase: root.scanPhase
            }

            Item { width: 1; height: 18 }

            /* The user name is an input that looks like a label until you
               click it, so a second account needs no separate screen. */
            TextInput {
                id: userField

                anchors.horizontalCenter: parent.horizontalCenter
                text: userModel.lastUser ? userModel.lastUser : ""
                horizontalAlignment: TextInput.AlignHCenter
                enabled: !root.authenticating
                color: activeFocus ? tok.line86 : tok.line62
                selectionColor: tok.line28
                selectedTextColor: tok.ink
                font.family: tok.mono
                font.pointSize: 12
                font.letterSpacing: 3.4
                renderType: Text.NativeRendering
                onAccepted: passwordField.takeFocus()

                Behavior on color { ColorAnimation { duration: tok.fast } }

                Rectangle {
                    anchors.top: parent.bottom
                    anchors.topMargin: 5
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: userField.activeFocus ? parent.width : 0
                    height: 1
                    color: tok.line42

                    Behavior on width {
                        NumberAnimation { duration: tok.base; easing.type: Easing.OutCubic }
                    }
                }
            }

            Item { width: 1; height: 30 }

            PasswordField {
                id: passwordField

                anchors.horizontalCenter: parent.horizontalCenter
                width: 380
                busy: root.authenticating
                capsLock: capsLockState.locked
                onAccepted: secret => root.beginLogin(secret)
            }

            Item { width: 1; height: 22 }

            /* Verdict line. One row high at all times so nothing below it
               moves when a message appears. */
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: core.width
                height: 20

                Text {
                    anchors.centerIn: parent
                    text: root.statusText
                    color: tok.line62
                    font.family: tok.mono
                    font.pointSize: 9.5
                    font.letterSpacing: 2.2
                    renderType: Text.NativeRendering
                    opacity: root.statusText.length > 0 ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: tok.base } }
                }
            }
        }

        /* Footer */
        Row {
            id: footer

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(parent.height * 0.075)
            spacing: 18

            GlyphButton {
                glyph: tok.glyphEye
                label: "EYE SCAN"
                enabled: !root.authenticating
                highlighted: root.scanPhase === "scanning"
                onClicked: root.beginLogin("")
            }

            GlyphButton {
                glyph: tok.glyphSession
                label: root.sessionName.toUpperCase()
                enabled: !root.authenticating && sessionModel.rowCount() > 1
                onClicked: root.cycleSession()
            }

            GlyphButton {
                glyph: tok.glyphKeyboard
                label: keyboard && keyboard.layouts.length > 0
                    ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase()
                    : "KEYBOARD"
                enabled: !root.authenticating && keyboard && keyboard.layouts.length > 1
                onClicked: root.cycleLayout()
            }

            Item { width: 26; height: 1 }

            GlyphButton {
                glyph: tok.glyphSleep
                label: "SLEEP"
                enabled: sddm.canSuspend === true && !root.authenticating
                onClicked: sddm.suspend()
            }

            GlyphButton {
                glyph: tok.glyphRestart
                label: "RESTART"
                enabled: sddm.canReboot === true && !root.authenticating
                onClicked: sddm.reboot()
            }

            GlyphButton {
                glyph: tok.glyphPower
                label: "SHUT DOWN"
                enabled: sddm.canPowerOff === true && !root.authenticating
                onClicked: sddm.powerOff()
            }
        }
    }

    /* Clicking anywhere that is not a control returns the caret to the
       secret, so a stray click never leaves the keyboard pointing nowhere. */
    TapHandler {
        onTapped: if (!root.authenticating) passwordField.takeFocus()
    }
}
