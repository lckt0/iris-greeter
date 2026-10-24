/*
    iris — lock-screen backdrop.

    A wallpaper plugin is the one surface Plasma 6 lets a theme paint on the
    lock screen without replacing the shell package that owns the unlock
    widget. It draws the same Backdrop.qml the SDDM theme draws, so the two
    screens share their ground, their frame, their corner marks and their
    caption; the unlock widget on top stays Plasma's own.

    It is the fallback used when the iris shell package is not active: a
    wallpaper has no access to the PAM conversation, so it shows no scanner.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    Backdrop {
        anchors.fill: parent
        caption: root.configuration["Caption"]
        showCaption: root.configuration["ShowCaption"]
    }
}
