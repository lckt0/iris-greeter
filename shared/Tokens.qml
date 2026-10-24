/*
    iris — design tokens.

    Every colour, duration and family the theme uses lives here and nowhere
    else. A plain QtObject rather than a qmldir singleton, so no import path
    has to be registered inside the greeter; each root instantiates
    `Tokens { id: tok }`.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

QtObject {
    /* The panel is OLED. The ground is not "very dark grey", it is unlit. */
    readonly property color ground: "#000000"
    readonly property color ink: "#ffffff"

    /* One white, seven weights. Everything drawn on this theme is one of
       these; no other colour is permitted anywhere in the theme. */
    readonly property color line06: Qt.rgba(1, 1, 1, 0.06)
    readonly property color line10: Qt.rgba(1, 1, 1, 0.10)
    readonly property color line16: Qt.rgba(1, 1, 1, 0.16)
    readonly property color line28: Qt.rgba(1, 1, 1, 0.28)
    readonly property color line42: Qt.rgba(1, 1, 1, 0.42)
    readonly property color line62: Qt.rgba(1, 1, 1, 0.62)
    readonly property color line86: Qt.rgba(1, 1, 1, 0.86)

    readonly property string mono: "JetBrainsMono Nerd Font"

    /* Nerd Font (Font Awesome) codepoints, written as escapes so they stay
       visible in diffs. */
    readonly property string glyphEye:      "\uf06e"
    readonly property string glyphSession:  "\uf108"
    readonly property string glyphKeyboard: "\uf11c"
    readonly property string glyphSleep:    "\uf186"
    readonly property string glyphRestart:  "\uf021"
    readonly property string glyphPower:    "\uf011"
    readonly property string glyphHibernate: "\uf2dc"
    readonly property string glyphUser:     "\uf2bd"

    readonly property int fast: 140
    readonly property int base: 260
    readonly property int slow: 480
    readonly property int veryLong: 900

    /* Must match the howdy timeout ([video] timeout in /etc/howdy/config.ini).
       The ring must never complete before pam_howdy does. Other scan timings
       are derived from this value. */
    readonly property int scanMs: 10000

    /* One sweep of the scan line, down or up. A fixed 1150 ms looked right
       over four seconds and frantic over ten; as a fraction it stays right. */
    readonly property int sweepMs: Math.round(scanMs * 0.29)

    /* How long a finished message stays on screen. Must outlast nothing —
       the screens hold it themselves while a scan is running — but it must
       not be so brief that a verdict is gone before it is read. */
    readonly property int holdMs: 3600
}
