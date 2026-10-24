pragma ComponentBehavior: Bound

/*
    iris — action button.

    A hairline ring with a glyph in it. The glyph comes from JetBrainsMono
    Nerd Font, which is installed under /usr/local/share/fonts and is
    therefore readable by the sddm user; an icon theme would not be, because
    the greeter runs out of its own profile and cannot see a 0700 home.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

Item {
    id: button

    property string glyph: ""
    property string label: ""
    property bool highlighted: false

    /* `enabled` is Item's own. Redeclaring it here would shadow the property
       the handlers below actually consult, and the button would keep taking
       taps while it looked disabled. */

    signal clicked()

    implicitWidth: 52
    implicitHeight: 52

    Tokens { id: tok }

    opacity: enabled ? 1 : 0.30
    Behavior on opacity { NumberAnimation { duration: tok.base } }

    readonly property bool lit: (hover.hovered || button.highlighted) && button.enabled

    Rectangle {
        id: ring

        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: button.lit ? tok.line62 : tok.line16

        Behavior on border.color { ColorAnimation { duration: tok.fast } }

        scale: press.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: tok.fast; easing.type: Easing.OutCubic } }
    }

    Text {
        anchors.centerIn: ring
        text: button.glyph
        color: button.lit ? tok.line86 : tok.line42
        font.family: tok.mono
        font.pointSize: 13
        renderType: Text.NativeRendering
        scale: ring.scale

        Behavior on color { ColorAnimation { duration: tok.fast } }
    }

    /* The name only appears when the pointer is on the button, so the footer
       stays a row of marks until you need words. */
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 9
        text: button.label
        color: tok.line42
        font.family: tok.mono
        font.pointSize: 7.5
        font.letterSpacing: 1.8
        renderType: Text.NativeRendering
        opacity: button.lit ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: tok.fast } }
    }

    HoverHandler {
        id: hover
        enabled: button.enabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: press
        enabled: button.enabled
        onTapped: button.clicked()
    }
}
