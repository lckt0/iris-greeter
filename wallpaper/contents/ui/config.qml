/*
    SPDX-FileCopyrightText: 2026 lckt0
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root

    property alias cfg_Caption: captionField.text
    property alias cfg_ShowCaption: captionCheck.checked

    QQC2.CheckBox {
        id: captionCheck
        Kirigami.FormData.label: "Corner caption:"
        text: "Show"
    }

    QQC2.TextField {
        id: captionField
        Kirigami.FormData.label: "Text:"
        enabled: captionCheck.checked
        placeholderText: "user@host"
    }
}
