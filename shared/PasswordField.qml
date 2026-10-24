pragma ComponentBehavior: Bound

/*
    iris — password field.

    Drawn from scratch: a rule, a caret and a row of bullets. The only thing
    borrowed is TextInput itself, because reimplementing text editing would
    mean reimplementing selection, clipboard, input methods and dead keys.

    The focus handling is the point of this file. A greeter window can be
    mapped before the compositor hands it keyboard focus, and anything typed
    in that window is dropped on the floor — which looks exactly like a
    rejected password, because PAM really does receive a truncated secret.
    Three defences, in order of how late they fire:

      1. takeFocus() on completion and again on a short timer;
      2. takeFocus() whenever the window becomes active;
      3. the screen root forwards any keystroke that arrives while this field
         is not focused (see Main.qml) into append(), so a key pressed during
         the race is typed rather than lost.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Window

Item {
    id: field

    property alias text: input.text
    property bool busy: false
    property bool capsLock: false
    property string placeholder: "Password"

    /* The three defences below fire on their own, which is right for a login
       screen that is always showing. A lock screen that rests dark needs the
       opposite: while nothing is on screen the field must NOT hold focus, or
       it swallows the very keystroke meant to wake the screen and types it
       into an invisible box. There, focus is handed over explicitly. */
    property bool autoFocus: true

    signal accepted(string secret)

    implicitWidth: 380
    implicitHeight: 58

    Tokens { id: tok }

    readonly property bool hasFocus: input.activeFocus
    readonly property bool empty: input.text.length === 0

    function takeFocus() {
        input.forceActiveFocus();
    }

    function append(s) {
        input.insert(input.cursorPosition, s);
    }

    function clear() {
        input.text = "";
    }

    function reject() {
        shake.restart();
    }

    Component.onCompleted: if (autoFocus) takeFocus()

    /* The window can take a moment to become focusable; ask again rather than
       assuming the first request landed. */
    Timer {
        running: true
        repeat: false
        interval: 220
        onTriggered: if (field.autoFocus) field.takeFocus()
    }

    Timer {
        running: true
        repeat: false
        interval: 700
        onTriggered: if (field.autoFocus) field.takeFocus()
    }

    /* Qualified through `field`: an attached property resolves against the
       nearest enclosing scope, and inside Connections that scope is the
       Connections object, which is not an Item. Unqualified, this silently
       binds to nothing and defence 2 never fires. */
    Connections {
        target: field.Window.window
        enabled: field.Window.window !== null

        function onActiveChanged() {
            if (field.autoFocus && field.Window.window && field.Window.window.active) {
                field.takeFocus();
            }
        }
    }

    SequentialAnimation {
        id: shake

        NumberAnimation { target: row; property: "x"; to: 9;  duration: 45 }
        NumberAnimation { target: row; property: "x"; to: -8; duration: 70 }
        NumberAnimation { target: row; property: "x"; to: 6;  duration: 70 }
        NumberAnimation { target: row; property: "x"; to: -4; duration: 70 }
        NumberAnimation { target: row; property: "x"; to: 0;  duration: 60 }
    }

    Item {
        id: row

        width: parent.width
        height: parent.height - 10
        opacity: field.busy ? 0.45 : 1

        Behavior on opacity { NumberAnimation { duration: tok.base } }

        /* Left-hand prompt mark. It is the only thing on screen that is not
           centred, and it gives the caret something to start from. */
        Text {
            id: prompt

            anchors.verticalCenter: parent.verticalCenter
            x: 0
            text: "›"
            color: field.hasFocus ? tok.line62 : tok.line28
            font.family: tok.mono
            font.pointSize: 15
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: tok.fast } }
        }

        TextInput {
            id: input

            anchors.verticalCenter: parent.verticalCenter
            x: prompt.x + prompt.width + 14
            width: parent.width - x - capsHint.width - 14

            enabled: !field.busy
            echoMode: TextInput.Password
            passwordCharacter: "•"
            passwordMaskDelay: 0

            color: tok.line86
            selectionColor: tok.line28
            selectedTextColor: tok.ink
            font.family: tok.mono
            font.pointSize: 13
            font.letterSpacing: 5
            renderType: Text.NativeRendering
            clip: true

            onAccepted: field.accepted(text)

            /* Drawn caret: the stock one is a platform rectangle and would be
               the only widget on screen this theme did not draw. */
            cursorDelegate: Rectangle {
                width: 1
                height: input.font.pointSize * 1.6
                color: tok.line86
                visible: input.activeFocus

                SequentialAnimation on opacity {
                    running: input.activeFocus
                    loops: Animation.Infinite

                    NumberAnimation { to: 0; duration: 520; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutQuad }
                }
            }
        }

        Text {
            id: placeholderLabel

            anchors.verticalCenter: parent.verticalCenter
            x: input.x + 1
            text: field.placeholder
            color: tok.line28
            font.family: tok.mono
            font.pointSize: 11
            font.letterSpacing: 2.4
            renderType: Text.NativeRendering
            visible: field.empty && !field.busy
            opacity: field.hasFocus ? 0.55 : 1

            Behavior on opacity { NumberAnimation { duration: tok.fast } }
        }

        Text {
            id: capsHint

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: "CAPS"
            color: tok.line62
            font.family: tok.mono
            font.pointSize: 8
            font.letterSpacing: 2
            renderType: Text.NativeRendering
            opacity: field.capsLock ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: tok.base } }
        }
    }

    /* Rule: a dim full-width hairline, with a bright one growing over it from
       the left when the field holds focus. */
    Rectangle {
        id: rule

        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: tok.line16
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: field.hasFocus ? parent.width : 0
        height: 1
        color: field.busy ? tok.line42 : tok.line86

        Behavior on width {
            NumberAnimation { duration: tok.slow; easing.type: Easing.OutCubic }
        }

        Behavior on color { ColorAnimation { duration: tok.base } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !field.busy
        onClicked: field.takeFocus()
    }
}
