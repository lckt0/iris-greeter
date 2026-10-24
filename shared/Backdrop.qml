pragma ComponentBehavior: Bound

/*
    iris — shared backdrop.

    This file is the entire visual bond between the login screen and the lock
    screen. It is installed twice, byte for byte:

      /usr/share/sddm/themes/iris/Backdrop.qml
      ~/.local/share/plasma/wallpapers/org.lckt0.iris/contents/ui/Backdrop.qml

    Everything it draws is derived from the screen rectangle alone — no font
    metrics, no grid units, no knowledge of the widgets in front of it — so the
    two screens cannot drift out of alignment no matter which greeter hosts it.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

Item {
    id: backdrop

    /* Printed inside the top-left corner: "user@host". */
    property string caption: ""
    property bool showCaption: true

    Tokens { id: tok }

    /* Frame inset and tick length track the short edge, clamped so the motif
       keeps its proportions from 1366x768 up to 4K. */
    readonly property real inset: Math.max(16, Math.min(52, Math.round(Math.min(width, height) * 0.028)))
    readonly property real tickLength: Math.max(18, Math.min(56, Math.round(Math.min(width, height) * 0.030)))
    readonly property real hair: 1
    readonly property real tickWeight: 2

    Rectangle {
        anchors.fill: parent
        color: tok.ground
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.margins: backdrop.inset
        color: "transparent"
        border.width: backdrop.hair
        border.color: tok.line06
    }

    /* Four L-shaped corner ticks, brighter than the frame they sit on.
       index: 0 = top-left, 1 = top-right, 2 = bottom-left, 3 = bottom-right. */
    Repeater {
        model: 4

        delegate: Item {
            id: corner

            required property int index

            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            readonly property real cx: atRight ? frame.x + frame.width : frame.x
            readonly property real cy: atBottom ? frame.y + frame.height : frame.y

            Rectangle {
                x: corner.atRight ? corner.cx - width : corner.cx
                y: corner.cy - backdrop.tickWeight / 2
                width: backdrop.tickLength
                height: backdrop.tickWeight
                color: tok.line28
            }

            Rectangle {
                x: corner.cx - backdrop.tickWeight / 2
                y: corner.atBottom ? corner.cy - height : corner.cy
                width: backdrop.tickWeight
                height: backdrop.tickLength
                color: tok.line28
            }
        }
    }

    /* A short graduated rule under the caption. */
    Row {
        id: rule

        spacing: Math.max(3, Math.round(backdrop.inset * 0.18))
        anchors.left: frame.left
        anchors.leftMargin: backdrop.tickLength + Math.round(backdrop.inset * 0.5)
        anchors.top: frame.top
        anchors.topMargin: Math.round(backdrop.inset * 1.55)
        visible: backdrop.showCaption

        Repeater {
            model: 12

            delegate: Rectangle {
                required property int index

                width: 1
                height: index % 4 === 0
                    ? Math.round(backdrop.tickLength * 0.26)
                    : Math.round(backdrop.tickLength * 0.13)
                color: index % 4 === 0 ? tok.line16 : tok.line10
            }
        }
    }

    Text {
        visible: backdrop.showCaption && text.length > 0
        text: backdrop.caption
        color: tok.line28
        font.family: tok.mono
        font.weight: Font.Light
        font.pointSize: 9
        font.letterSpacing: 1.6
        renderType: Text.NativeRendering
        anchors.left: frame.left
        anchors.top: frame.top
        anchors.leftMargin: backdrop.tickLength + Math.round(backdrop.inset * 0.5)
        anchors.topMargin: Math.round(backdrop.inset * 0.45)
    }
}
