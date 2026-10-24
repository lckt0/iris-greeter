/*
    iris — session start-up.

    The seam this closes: SDDM ends with the eye matched, and a moment later
    the desktop appears. In between, stock Plasma shows an unrelated logo. Here
    the same eye stays on screen, in the same place, at the same size, and the
    ring that measured the scan now measures the session coming up.

    ksplashqml owns `stage`. It counts 1..6 as start-up proceeds, so the ring is
    a real measure rather than a guessed animation — which is why IrisScanner's
    `progress` is driven from here instead of letting it run its own timer.

    This is a look-and-feel package containing nothing but a splash. Selecting
    it through ksplashrc's [KSplash] Theme changes the start-up picture and
    nothing else: it is not applied as a global theme, so colours, icons and
    the desktop layout are untouched.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

Rectangle {
    id: root

    color: "#000000"

    /* Set by ksplashqml. */
    property int stage: 0

    Tokens { id: tok }
    Caption { id: captionSource }

    /* 1 is "started", 6 is "done"; the ring spans the part the user waits
       through. Clamped, because a future Plasma is free to count differently
       and a ring past 360 degrees would wrap and read as a restart. */
    readonly property real progress: Math.max(0, Math.min(1, (stage - 1) / 4))

    Backdrop {
        anchors.fill: parent
        caption: captionSource.text
        showCaption: true
        opacity: content.opacity
    }

    /* Painted from the first frame rather than faded in at stage 2 like the
       stock splash, so the handover from the greeter is as short as it can be. */
    Item {
        id: content

        anchors.fill: parent
        opacity: 1

        Column {
            /* Same anchor, same offset, same eye size as Main.qml and
               LockScreenUi.qml, so the scanner does not move when one screen
               hands over to the next. */
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Math.round(parent.height * 0.045)
            spacing: 0

            IrisScanner {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 208
                height: 208

                /* "working", not "scanning": the iris turns and the ring fills,
                   but there is no sweep line and no sensor readout, because
                   nothing is being read — the session is loading. */
                phase: root.stage >= 5 ? "matched" : "working"
                progress: root.progress
            }

            Item { width: 1; height: 18 }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.stage >= 5 ? "session ready" : "starting session"
                color: tok.line62
                font.family: tok.mono
                font.pointSize: 12
                font.letterSpacing: 3.4
                renderType: Text.NativeRendering
            }
        }
    }
}
