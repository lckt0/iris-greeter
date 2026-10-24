/*
    iris — lock screen.

    Deliberately the same screen as the login one: same backdrop, same clock,
    same scanner, same password field, same status line, same footer marks,
    at the same positions. Differences: the user name is fixed, there is no
    session picker, the footer offers sleep / hibernate / switch user, and the
    face scan starts by itself (kscreenlocker keeps the PAM conversation open,
    so a failed scan does not count as a faillock attempt).

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.plasma.private.sessions

/* FocusScope rather than Item: inside the Loader's focus scope a plain Item
   loses active focus to the Loader and keystrokes are dropped until a click. */
FocusScope {
    id: lockScreenUi

    /* Needed for Keys.onPressed below: before anything inside has taken
       focus, this is what receives the first keystroke. */
    focus: true

    Tokens { id: tok }
    ScanStatus { id: interpreter }
    Caption { id: caption }

    SessionManagement { id: sessionManagement }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    property string scanPhase: "idle"
    property string statusText: ""

    /* A short message from the screen itself, shown in the status line for
       `holdMs`. A new message from PAM replaces it immediately. */
    property string hintText: ""

    function hint(text) {
        lockScreenUi.hintText = text;
        hintTimer.restart();
    }

    Timer {
        id: hintTimer
        interval: tok.holdMs
        onTriggered: lockScreenUi.hintText = ""
    }

    /* Is a PAM conversation open right now? kscreenlocker's
       startAuthenticating() returns early while one is, so a rescan is not
       possible until a password has been rejected. Prefer
       `authenticator.state` when it exists, otherwise use our own count. */
    property bool conversationOpen: false

    readonly property bool authenticating:
        typeof authenticator.state === "number"
            ? authenticator.state === 1
            : lockScreenUi.conversationOpen

    /* One door in, so the flag cannot drift away from the call. */
    function beginAuthentication() {
        lockScreenUi.conversationOpen = true;
        authenticator.startAuthenticating();
    }

    /* PAM answered yes without ever asking for a secret — a face, in other
       words. kscreenlocker's own UI swaps in a confirm-to-unlock screen here
       rather than dropping straight into the session, and so do we. */
    property bool unlockOffered: false

    readonly property string userName: typeof kscreenlocker_userName !== "undefined"
        ? kscreenlocker_userName
        : ""

    /* ------------------------------------------------------------------ */
    /*  authentication                                                     */
    /* ------------------------------------------------------------------ */

    function absorb(message) {
        const verdict = interpreter.classify(message);
        if (verdict === null) {
            return;
        }
        if (verdict.phase.length > 0) {
            lockScreenUi.scanPhase = verdict.phase;
        }
        /* PAM has just said something; whatever this screen was saying in the
           meantime steps aside for it rather than covering it up. */
        lockScreenUi.hintText = "";
        hintTimer.stop();
        lockScreenUi.statusText = verdict.text;
        root.notification = verdict.text;
        forgetTimer.restart();
    }

    Connections {
        target: authenticator

        function onSucceeded() {
            lockScreenUi.conversationOpen = false;
            if (authenticator.hadPrompt) {
                Qt.quit();
            } else {
                /* No prompt means this was the scanner, so say so and wait
                   for a deliberate keypress before opening the session. */
                lockScreenUi.scanPhase = "matched";
                lockScreenUi.statusText = "Iris matched";
                lockScreenUi.unlockOffered = true;
                unlockButton.forceActiveFocus();
            }
        }

        function onFailed(kind) {
            /* kind != 0 is a non-interactive authenticator (fingerprint,
               smartcard) reporting for itself; the password path is kind 0. */
            if (kind !== 0) {
                return;
            }
            /* Only kind 0 closes anything: the others are non-interactive
               authenticators reporting for themselves, and the interactive
               conversation carries on regardless. */
            lockScreenUi.conversationOpen = false;
            if (lockScreenUi.scanPhase === "scanning") {
                lockScreenUi.scanPhase = "failed";
            }
            if (lockScreenUi.statusText.length === 0) {
                lockScreenUi.statusText = "Unlocking failed";
            }
            root.notification = lockScreenUi.statusText;
            passwordField.clear();
            passwordField.reject();
            passwordField.takeFocus();
            graceLockTimer.restart();
            forgetTimer.restart();
        }

        function onInfoMessageChanged() {
            lockScreenUi.absorb(authenticator.infoMessage);
        }

        function onErrorMessageChanged() {
            lockScreenUi.absorb(authenticator.errorMessage);
        }

        function onPromptChanged() {
            lockScreenUi.absorb(authenticator.prompt);
        }

        function onPromptForSecretChanged() {
            passwordField.takeFocus();
        }
    }

    Connections {
        target: root

        function onClearPassword() {
            passwordField.clear();
            passwordField.takeFocus();
        }
    }

    Connections {
        target: sessionManagement

        function onAboutToSuspend() {
            root.clearPassword();
        }
    }

    /* After a rejection PAM needs a moment before it will listen again; the
       stock screen waits three seconds and restarts the conversation, which
       is also what re-arms the scanner. */
    Timer {
        id: graceLockTimer
        interval: 3000
        onTriggered: {
            root.clearPassword();
            lockScreenUi.beginAuthentication();
        }
    }

    Timer {
        id: forgetTimer
        interval: tok.holdMs
        onTriggered: {
            /* Never clear mid-scan: pam_howdy sends one notice and then stays
               silent for its whole timeout. */
            if (lockScreenUi.scanPhase === "scanning" || lockScreenUi.unlockOffered) {
                forgetTimer.restart();
                return;
            }
            lockScreenUi.scanPhase = "idle";
            lockScreenUi.statusText = "";
            root.notification = "";
        }
    }

    /* Keep the secret the same across every screen's view. Guarded rather
       than two-way bound: a plain comparison cannot loop, and clear() does
       not have to re-establish a binding it just destroyed. */
    onStatusTextChanged: if (statusText.length > 0) forgetTimer.restart()

    Connections {
        target: PasswordSync

        function onPasswordChanged() {
            if (passwordField.text !== PasswordSync.password) {
                passwordField.text = PasswordSync.password;
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /*  idle behaviour                                                     */
    /* ------------------------------------------------------------------ */

    /* The screen sits dark until a key is pressed, which also keeps the
       camera off until someone is actually there. The mouse deliberately
       does not wake it (a bumped touchpad would start a scan). This
       MouseArea only hides the cursor and swallows stray clicks. */
    MouseArea {
        id: surface

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: uiVisible ? Qt.ArrowCursor : Qt.BlankCursor

        property bool uiVisible: false

        readonly property bool holdOpen: passwordField.text.length > 0
            || lockScreenUi.unlockOffered

        onUiVisibleChanged: {
            if (uiVisible) {
                if (Window.window) {
                    Window.window.requestActivate();
                }
                passwordField.takeFocus();
                lockScreenUi.beginAuthentication();
                fadeoutTimer.restart();
            }
        }

        onHoldOpenChanged: {
            if (holdOpen) {
                fadeoutTimer.stop();
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
        }

        Timer {
            id: fadeoutTimer
            interval: 30000
            onTriggered: {
                if (!surface.holdOpen) {
                    surface.uiVisible = false;
                }
            }
        }
    }

    /* Holds focus while the screen rests, so any key (Enter included) wakes
       it. A printable key also lands in the password field. */
    Item {
        id: wakeCatcher

        anchors.fill: parent
        focus: !surface.uiVisible

        Keys.onPressed: event => {
            surface.uiVisible = true;

            const printable = event.text.length === 1
                && event.text.charCodeAt(0) >= 0x20
                && event.text.charCodeAt(0) !== 0x7f
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));

            if (printable) {
                passwordField.append(event.text);
            }
            event.accepted = true;
        }
    }

    Keys.onPressed: event => {
        surface.uiVisible = true;
        fadeoutTimer.restart();

        if (lockScreenUi.unlockOffered) {
            event.accepted = false;
            return;
        }

        /* Same defence as the login screen: a key that arrives before the
           field holds focus is typed rather than dropped. */
        if (!passwordField.hasFocus) {
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

    /* ------------------------------------------------------------------ */
    /*  scene — laid out to match the login screen                         */
    /* ------------------------------------------------------------------ */

    Backdrop {
        anchors.fill: parent
        caption: caption.text
        showCaption: true
    }

    /* The clock lives outside `stage` so it does not fade with everything
       else: at rest it is the whole screen, and waking the screen leaves it
       exactly where it was while the rest arrives around it. */
    Column {
        id: clock

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height * 0.14)
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(lockScreenUi.now, "HH:mm")
            color: surface.uiVisible ? tok.line86 : tok.line62
            font.family: tok.mono
            font.weight: Font.ExtraLight
            font.pointSize: 52
            font.letterSpacing: 6
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: tok.veryLong } }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(lockScreenUi.now, "dddd, d MMMM").toLowerCase()
            color: tok.line28
            font.family: tok.mono
            font.weight: Font.Light
            font.pointSize: 10
            font.letterSpacing: 4
            renderType: Text.NativeRendering
        }
    }

    /* Shown only while the screen rests. */
    Column {
        id: resting

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: clock.bottom
        anchors.topMargin: Math.round(parent.height * 0.055)
        spacing: 16

        opacity: surface.uiVisible ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: tok.veryLong; easing.type: Easing.InOutQuad }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 1
                color: tok.line16
            }

            Text {
                text: "MACHINE LOCKED"
                color: tok.line42
                font.family: tok.mono
                font.weight: Font.Light
                font.pointSize: 10
                font.letterSpacing: 5
                renderType: Text.NativeRendering
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 1
                color: tok.line16
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "press any key"
            color: tok.line16
            font.family: tok.mono
            font.pointSize: 8
            font.letterSpacing: 3
            renderType: Text.NativeRendering
        }
    }

    Item {
        id: stage

        anchors.fill: parent
        opacity: surface.uiVisible ? 1 : 0
        visible: opacity > 0
        enabled: surface.uiVisible

        Behavior on opacity {
            NumberAnimation { duration: tok.veryLong; easing.type: Easing.InOutQuad }
        }

        Column {
            id: core

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Math.round(parent.height * 0.045)
            spacing: 0

            IrisScanner {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 208
                height: 208
                phase: lockScreenUi.scanPhase
            }

            Item { width: 1; height: 18 }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: lockScreenUi.userName
                color: tok.line62
                font.family: tok.mono
                font.pointSize: 12
                font.letterSpacing: 3.4
                renderType: Text.NativeRendering
            }

            Item { width: 1; height: 30 }

            /* One slot, two occupants: the secret, or the confirmation that
               the scanner already answered. Same height either way, so
               nothing below shifts when they swap. */
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 380
                height: 58

                PasswordField {
                    id: passwordField

                    anchors.fill: parent
                    /* Focus is handed over explicitly by onUiVisibleChanged.
                       If the field grabbed it on its own, it would swallow the
                       keystroke meant to wake the screen and type it into a box
                       nobody can see. */
                    autoFocus: false
                    capsLock: capsLockState.locked
                    /* authenticator.graceLocked does not exist in current
                       kscreenlocker; graceLockTimer tracks the same state. */
                    busy: graceLockTimer.running
                    opacity: lockScreenUi.unlockOffered ? 0 : 1
                    visible: opacity > 0
                    enabled: !lockScreenUi.unlockOffered

                    Behavior on opacity { NumberAnimation { duration: tok.base } }

                    onAccepted: secret => {
                        PasswordSync.password = secret;
                        authenticator.respond(secret);
                    }

                    onTextChanged: PasswordSync.password = text
                }

                Item {
                    id: unlockButton

                    anchors.fill: parent
                    opacity: lockScreenUi.unlockOffered ? 1 : 0
                    visible: opacity > 0
                    focus: lockScreenUi.unlockOffered

                    Behavior on opacity { NumberAnimation { duration: tok.base } }

                    Keys.onReturnPressed: Qt.quit()
                    Keys.onEnterPressed: Qt.quit()
                    Keys.onSpacePressed: Qt.quit()

                    Text {
                        anchors.centerIn: parent
                        text: "press enter to unlock"
                        color: tok.line86
                        font.family: tok.mono
                        font.pointSize: 11
                        font.letterSpacing: 3
                        renderType: Text.NativeRendering
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: tok.line42
                    }

                    TapHandler {
                        onTapped: Qt.quit()
                    }
                }
            }

            Item { width: 1; height: 22 }

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: core.width
                height: 20

                Text {
                    anchors.centerIn: parent
                    text: {
                        const parts = [];
                        if (capsLockState.locked) {
                            parts.push("CAPS LOCK");
                        }
                        /* One message at a time, so the line stays within the
                           380 px column. */
                        const said = lockScreenUi.hintText.length > 0
                            ? lockScreenUi.hintText
                            : lockScreenUi.statusText;
                        if (said.length > 0) {
                            parts.push(said);
                        }
                        return parts.join("  •  ");
                    }
                    color: tok.line62
                    font.family: tok.mono
                    font.pointSize: 9.5
                    font.letterSpacing: 2.2
                    renderType: Text.NativeRendering
                    opacity: text.length > 0 ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: tok.base } }
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(parent.height * 0.075)
            spacing: 18

            GlyphButton {
                id: scanButton

                glyph: tok.glyphEye
                label: "SCAN AGAIN"
                highlighted: lockScreenUi.scanPhase === "scanning"
                enabled: !lockScreenUi.unlockOffered
                onClicked: {
                    /* Stays enabled when a scan cannot start; pressing it then
                       explains why instead. */
                    if (lockScreenUi.authenticating) {
                        lockScreenUi.hint(lockScreenUi.scanPhase === "scanning"
                            ? "Scan already running"
                            : "Scanner busy, use password");
                        return;
                    }

                    lockScreenUi.scanPhase = "idle";
                    lockScreenUi.statusText = "";
                    lockScreenUi.beginAuthentication();
                    passwordField.takeFocus();
                }
            }

            Item { width: 26; height: 1 }

            GlyphButton {
                glyph: tok.glyphSleep
                label: "SLEEP"
                enabled: sessionManagement.canSuspend === true
                onClicked: sessionManagement.suspend()
            }

            GlyphButton {
                glyph: tok.glyphHibernate
                label: "HIBERNATE"
                enabled: sessionManagement.canHibernate === true
                onClicked: sessionManagement.hibernate()
            }

            GlyphButton {
                glyph: tok.glyphUser
                label: "SWITCH USER"
                enabled: sessionManagement.canSwitchUser === true
                onClicked: sessionManagement.switchUser()
            }
        }
    }

    /* ---- clock tick ---- */

    property date now: new Date()

    Timer {
        running: true
        repeat: true
        interval: 1000
        onTriggered: lockScreenUi.now = new Date()
    }
}
