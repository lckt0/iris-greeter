/*
    iris — shared secret between the per-screen lock views.

    kscreenlocker puts one view on every screen and they share a QML engine,
    so a singleton is what keeps the secret the same on all of them: type on
    the laptop panel, and the external monitor's field agrees. Same shape as
    the one the stock shell package ships, because kscreenlocker's own
    LockScreen contract is what defines it.

    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

pragma Singleton

import QtQuick

QtObject {
    property string password
}
