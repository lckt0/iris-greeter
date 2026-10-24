/*
    iris — lock screen entry point.

    kscreenlocker looks for specific members on this object by name — the
    "magical properties" the stock package documents — so their names and
    types are not ours to choose:

      viewVisible          set by kscreenlocker when the view is shown
      notification         we write, it reads
      clearPassword()      emitted at us, e.g. just before suspend
      notificationRepeated()  emitted at us when a message repeats

    The real interface is loaded through a Loader rather than instantiated
    directly, so that a UI which fails to load — a module gone after a Plasma
    upgrade, a syntax error in a file someone edited — falls back to a plain
    password prompt instead of leaving a locked session with nothing to type
    into.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

Item {
    id: root

    property bool debug: false
    property string notification
    signal clearPassword()
    signal notificationRepeated()

    // Magical property: kscreenlocker looks for this one by name.
    property bool viewVisible: false

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    implicitWidth: 800
    implicitHeight: 600

    /* Set once we have given up on the real UI, so a fallback that also fails
       cannot put the Loader in a loop. */
    property bool fellBack: false

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    Loader {
        id: ui

        anchors.fill: parent
        source: "LockScreenUi.qml"
        asynchronous: false
        focus: true

        onStatusChanged: {
            if (status === Loader.Error && !root.fellBack) {
                root.fellBack = true;
                console.warn("iris: LockScreenUi failed to load, falling back to the plain prompt");
                source = "FallbackUi.qml";
            }
        }
    }
}
