/*
    iris — the corner caption.

    The login screen reads its caption from theme.conf, which SDDM parses and
    hands to the theme as `config.caption`. The lock screen has no equivalent:
    kscreenlocker gives a shell package no configuration of its own, and QML
    cannot read the host name. So the value is compiled in, and install.sh
    rewrites the line below with the same string it writes into theme.conf.

    Change it with `IRIS_CAPTION=... ./install.sh`, or edit both files.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

QtObject {
    // install.sh rewrites this line; keep it on one line.
    readonly property string text: "user@host"
}
